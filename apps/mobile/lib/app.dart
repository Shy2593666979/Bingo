import 'dart:async';

import 'package:bingo/core/config/app_config.dart';
import 'package:bingo/core/device/device_tool_executor.dart';
import 'package:bingo/core/preferences/call_preferences_store.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/push/push_registration_service.dart';
import 'package:bingo/features/app_shell.dart';
import 'package:bingo/features/auth/data/auth_token_store.dart';
import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/auth/presentation/auth_page.dart';
import 'package:bingo/features/auth/presentation/profile_setup_page.dart';
import 'package:bingo/features/chat/data/chat_gateway.dart';
import 'package:bingo/features/chat/data/local_chat_store.dart';
import 'package:bingo/features/chat/presentation/chat_controller.dart';
import 'package:bingo/features/splash/presentation/splash_page.dart';
import 'package:flutter/material.dart';

class BingoApp extends StatefulWidget {
  const BingoApp({this.tokenStore, super.key});

  final TokenStore? tokenStore;

  @override
  State<BingoApp> createState() => _BingoAppState();
}

class _BingoAppState extends State<BingoApp> with WidgetsBindingObserver {
  late final AppConfig _config;
  late final HttpApiGateway _gateway;
  late final ChatController _controller;
  late final LocalChatStore _localChatStore;
  late final TokenStore _tokenStore;
  late final PushRegistrationService _pushRegistration;
  late final CallPreferencesStore _callPreferencesStore;
  bool _showSplash = true;
  bool _sessionResolved = false;
  bool _callCaptionsEnabled = false;
  UserProfile? _profile;
  Timer? _engagementTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _config = AppConfig.fromEnvironment();
    _gateway = HttpApiGateway(config: _config);
    _localChatStore = AndroidLocalChatStore();
    _controller = ChatController(
      gateway: _gateway,
      deviceActions: _gateway,
      deviceToolExecutor: AndroidDeviceToolExecutor(),
      localStore: _localChatStore,
      remoteHistory: _gateway,
      engagement: _gateway,
    );
    _tokenStore = widget.tokenStore ?? AuthTokenStore();
    _callPreferencesStore = CallPreferencesStore();
    _pushRegistration = PushRegistrationService(
      gateway: _gateway,
    );
    unawaited(_pushRegistration.initialize());
    unawaited(_loadCallPreferences());
    unawaited(_restoreSession());
    _engagementTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_controller.refreshEngagement()),
    );
  }

  Future<void> _loadCallPreferences() async {
    final enabled = await _callPreferencesStore.readCaptionsEnabled();
    if (mounted) setState(() => _callCaptionsEnabled = enabled);
  }

  Future<void> _setCallCaptionsEnabled(bool enabled) async {
    final previous = _callCaptionsEnabled;
    if (mounted) setState(() => _callCaptionsEnabled = enabled);
    try {
      await _callPreferencesStore.writeCaptionsEnabled(enabled);
    } on Exception {
      if (mounted) setState(() => _callCaptionsEnabled = previous);
      rethrow;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.syncActiveConversation());
      unawaited(_controller.refreshEngagement());
    }
  }

  Future<void> _restoreSession() async {
    try {
      final token = await _tokenStore.read();
      if (token != null) {
        _gateway.accessToken = token;
        _profile = await _gateway.getProfile();
        _controller.setAssistantRole(_profile!.role);
        await _controller.bindUser(_profile!.id);
        if (_profile!.onboardingComplete) {
          await _pushRegistration.activate();
        }
      }
    } on Exception {
      _gateway.accessToken = null;
      await _tokenStore.clear();
    } finally {
      if (mounted) setState(() => _sessionResolved = true);
    }
  }

  Future<void> _onAuthenticated(AuthResult result) async {
    _gateway.accessToken = result.accessToken;
    await _tokenStore.write(result.accessToken);
    _controller.setAssistantRole(result.user.role);
    await _controller.bindUser(result.user.id);
    if (result.user.onboardingComplete) {
      await _pushRegistration.activate();
    }
    if (mounted) setState(() => _profile = result.user);
  }

  Future<void> _logout() async {
    await _pushRegistration.deactivate();
    try {
      await _gateway.logout();
    } on Exception {
      // Local logout must still succeed when the server is unavailable.
    }
    await _tokenStore.clear();
    _gateway.accessToken = null;
    _controller.unbindUser();
    if (mounted) {
      setState(() {
        _profile = null;
      });
    }
  }

  Future<void> _onProfileSaved(UserProfile updated) async {
    _controller.setAssistantRole(updated.role);
    setState(() {
      _profile = updated;
    });
    await _pushRegistration.activate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engagementTimer?.cancel();
    _gateway.close();
    unawaited(_localChatStore.close());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bingo',
      debugShowCheckedModeBanner: false,
      theme: buildBingoTheme(),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        child: _buildHome(),
      ),
    );
  }

  Widget _buildHome() {
    if (_showSplash) {
      return SplashPage(
        key: const ValueKey('splash'),
        onFinished: () {
          if (mounted) setState(() => _showSplash = false);
        },
      );
    }
    if (!_sessionResolved) {
      return const Scaffold(
        key: ValueKey('session-loading'),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final profile = _profile;
    if (profile == null) {
      return AuthPage(
        key: const ValueKey('auth'),
        gateway: _gateway,
        onAuthenticated: _onAuthenticated,
      );
    }
    if (!profile.onboardingComplete) {
      return ProfileSetupPage(
        key: const ValueKey('profile-setup'),
        gateway: _gateway,
        profile: profile,
        onSaved: _onProfileSaved,
      );
    }
    return AppShell(
      key: const ValueKey('app'),
      chatController: _controller,
      gateway: _gateway,
      profile: profile,
      callCaptionsEnabled: _callCaptionsEnabled,
      onCallCaptionsChanged: _setCallCaptionsEnabled,
      onProfileSaved: _onProfileSaved,
      onLogout: _logout,
    );
  }
}
