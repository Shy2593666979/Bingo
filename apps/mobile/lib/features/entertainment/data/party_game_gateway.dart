import 'dart:io';
import 'package:bingo/features/entertainment/domain/game_setup.dart';

abstract interface class PartyGameGateway {
  Future<Map<String, dynamic>> createPartyGame(GameSetup setup);
  Future<List<Map<String, dynamic>>> listPartyGames();
  Future<Map<String, dynamic>> getPartyGame(String id);
  Future<Map<String, dynamic>> partyGameAction(
      String id, String type, String value, int revision, String commandId,
      {String stage = ''});
  Future<WebSocket> connectPartyVoice(String id);
}
