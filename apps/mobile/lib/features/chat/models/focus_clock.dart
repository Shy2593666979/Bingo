class FocusClock {
  FocusClock(
      {required this.totalSeconds,
      required this.remainingSeconds,
      this.deadline,
      this.completed = false});
  final int totalSeconds;
  int remainingSeconds;
  DateTime? deadline;
  bool completed;

  int remaining(DateTime now) => deadline == null
      ? remainingSeconds
      : ((deadline!.difference(now).inMilliseconds + 999) ~/ 1000)
          .clamp(0, totalSeconds);

  void resume(DateTime now) {
    if (!completed && deadline == null) {
      deadline = now.add(Duration(seconds: remainingSeconds));
    }
  }

  void pause(DateTime now) {
    remainingSeconds = remaining(now);
    deadline = null;
  }

  Map<String, dynamic> toJson() => {
        'total': totalSeconds,
        'remaining': remainingSeconds,
        'deadline': deadline?.toIso8601String(),
        'completed': completed
      };

  factory FocusClock.fromJson(Map<String, dynamic> json) => FocusClock(
      totalSeconds: json['total'] as int,
      remainingSeconds: json['remaining'] as int,
      deadline: json['deadline'] == null
          ? null
          : DateTime.parse(json['deadline'] as String),
      completed: json['completed'] == true);
}
