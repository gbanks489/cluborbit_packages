import 'package:flutter_test/flutter_test.dart';

import 'package:clubcommon/clubcommon.dart';

void main() {
  test('User serializes and deserializes', () {
    final profile = User(
      uid: 'u1',
      email: 'test@cluborbit.com',
      firstName: 'Club',
      lastName: 'Orbit',
      displayName: 'Club Orbit',
      activities: <String>['Pickleball'],
    );

    final json = profile.toJson();
    final parsed = User.fromJson(json);

    expect(parsed.uid, profile.uid);
    expect(parsed.email, profile.email);
    expect(parsed.displayName, profile.displayName);
    expect(parsed.activities, profile.activities);
  });
}
