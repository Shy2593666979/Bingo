/// Default portraits whose backdrop should show the surrounding page.
const transparentRoleAvatarCodes = {
  'girlfriend',
  'boyfriend',
  'colleague',
  'teacher',
  'parent',
  'child',
  'bestie',
  'bro',
  'senior_sister',
  'senior_brother',
  'confidant',
  'fitness',
  'chairman',
  'executive',
};

bool isTransparentRoleAvatarAsset(String asset) =>
    transparentRoleAvatarCodes.contains(asset.split('/').last.split('.').first);

/// Built-in avatar names accepted from role and community responses.
const roleAvatarFiles = <String>{
  'bingo_logo.png',
  'girlfriend.png',
  'boyfriend.png',
  'colleague.png',
  'teacher.png',
  'parent.png',
  'child.png',
  'bestie.png',
  'bro.png',
  'senior_sister.png',
  'senior_brother.png',
  'confidant.png',
  'fitness.png',
  'chairman.png',
  'executive.png',
};
