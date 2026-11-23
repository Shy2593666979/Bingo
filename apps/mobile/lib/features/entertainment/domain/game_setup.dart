import 'package:bingo/features/auth/models/auth_models.dart';
import 'package:bingo/features/group_chat/data/group_gateway.dart';

enum CompanionGame {
  truth('真心话大冒险', '聊点没聊过的，发现搭子的另一面。', '约 3～8 分钟'),
  wolf('狼人杀', '听理由、藏身份，和熟悉的搭子一起推理。', '约 12～20 分钟');

  const CompanionGame(this.title, this.description, this.duration);
  final String title, description, duration;
}

class GameCompanion {
  const GameCompanion(
      {required this.id, required this.name, required this.avatarKey});
  factory GameCompanion.fromRole(RoleOption role) =>
      GameCompanion(id: role.id, name: role.displayName, avatarKey: role.name);
  factory GameCompanion.fromMember(GroupPerson member) => GameCompanion(
      id: member.id, name: member.name, avatarKey: member.roleName);
  final String id, name, avatarKey;
}

/// Client preferences only. Identities, private knowledge and all rules are server-owned.
class GameSetup {
  GameSetup(
      {required this.game,
      required List<GameCompanion> companions,
      this.groupId,
      this.groupName,
      this.rounds = 5,
      this.wolfSeats = 7,
      this.identity,
      this.mood = '朋友派对'})
      : companions = List.unmodifiable(companions);
  final CompanionGame game;
  final List<GameCompanion> companions;
  final String? groupId, groupName;
  final String? identity;
  final int rounds, wolfSeats;
  final String mood;
  String get roomName =>
      groupName ?? (game == CompanionGame.truth ? '真心话小聚' : '搭子推理局');
  int get players => companions.length + 1;
  String? get validationError {
    if (companions.map((p) => p.id).toSet().length != companions.length) {
      return '同一位搭子不能重复加入';
    }
    if (game == CompanionGame.truth) {
      if (companions.length < 2 || companions.length > 5) return '请选择 2～5 位搭子';
      if (![3, 5, 8].contains(rounds)) return '请选择 3、5 或 8 轮';
    } else {
      if (![5, 7].contains(wolfSeats)) return '狼人杀仅支持 5 人或 7 人局';
      if (players != wolfSeats) return '$wolfSeats 人局需要你和 ${wolfSeats - 1} 位搭子';
    }
    return null;
  }
}
