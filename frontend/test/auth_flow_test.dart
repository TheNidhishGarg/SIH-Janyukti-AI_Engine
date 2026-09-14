import 'package:janyukti/features/auth/providers/user_provider.dart';
import 'package:janyukti/features/auth/views/session_gate.dart';
import 'package:janyukti/core/localization/app_localizations.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:janyukti/apis/auth_api.dart';
import 'package:janyukti/core/routes/app_routes.dart';
import 'package:janyukti/features/auth/controllers/auth_controller.dart';
import 'package:janyukti/features/auth/views/registration_screen.dart';
import 'package:janyukti/models/registration_data.dart';
import 'package:janyukti/models/user_model.dart';
import 'package:janyukti/models/user_role.dart';

class FakeApi implements AuthApi {
  UserModel profile = const UserModel(
    uid: 'test',
    role: UserRole.citizen,
    status: 'active',
  );
  int loginCalls = 0;
  bool signedOut = false;
  Completer<void>? waitForLogin;
  @override
  Future<UserCredential> login({
    required String email,
    required String password,
  }) async {
    loginCalls++;
    await waitForLogin?.future;
    return FakeCredential();
  }

  @override
  Future<UserModel> requireProfile(UserRole? role) async {
    if (role != profile.role) {
      throw const AccountException(
        'This account does not belong to the selected portal.',
      );
    }
    return profile;
  }

  @override
  Future<void> logout() async {
    signedOut = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SessionApi extends FakeApi {
  final profiles = StreamController<UserModel?>();
  @override
  User? get currentUser => FakeUser();
  @override
  Stream<User?> authChanges() => Stream.value(FakeUser());
  @override
  Stream<UserModel?> watchUserProfile(String uid) => profiles.stream;
}

class FakeUser implements User {
  FakeUser([this.uid = 'test']);
  @override
  final String uid;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class PersistentSessionApi extends FakeApi {
  User? account = FakeUser();
  final changes = StreamController<User?>.broadcast();
  final documents = <String, StreamController<UserModel?>>{};
  int watches = 0;
  @override
  User? get currentUser => account;
  @override
  Stream<User?> authChanges() async* {
    yield account;
    yield* changes.stream;
  }

  @override
  Stream<UserModel?> watchUserProfile(String uid) {
    watches++;
    return document(uid).stream;
  }

  StreamController<UserModel?> document(String uid) => documents.putIfAbsent(
    uid,
    () => StreamController<UserModel?>.broadcast(),
  );
  void switchAccount(User? value) {
    account = value;
    changes.add(value);
  }

  @override
  Future<void> logout() async {
    signedOut = true;
    switchAccount(null);
  }

  Future<void> close() async {
    await changes.close();
    for (final stream in documents.values) {
      await stream.close();
    }
  }
}

class FakeCredential implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RegistrationData data(
  UserRole role, {
  String password = 'secure123',
  String confirm = 'secure123',
  String category = 'Other',
}) => RegistrationData(
  role: role,
  fullName: 'Test Person',
  email: 'test@example.com',
  password: password,
  confirmPassword: confirm,
  organizationName: 'Test Organization',
  category: category,
  phone: '9876543210',
  address: 'Test Address',
  city: 'Delhi',
  state: 'Delhi',
  designation: 'Coordinator',
);
void main() {
  test(
    'registration validation covers all roles, password mismatch and required organization fields',
    () {
      for (final role in UserRole.values) {
        expect(data(role).validate(), isNull);
      }
      expect(
        data(UserRole.citizen, password: '123').validate(),
        contains('6 characters'),
      );
      expect(
        data(UserRole.admin, confirm: 'different').validate(),
        contains('match'),
      );
      expect(
        data(UserRole.university, category: '').validate(),
        contains('required organization'),
      );
      expect(RegistrationData.validEmail('bad-email'), isFalse);
    },
  );
  test('missing status fails closed and invalid stored roles are rejected', () {
    expect(UserModel.fromMap('id', {'role': 'admin'}).isActive, isFalse);
    expect(
      () => UserModel.fromMap('id', {'role': 'owner'}),
      throwsFormatException,
    );
  });
  for (final role in UserRole.values) {
    for (final status in ['active', 'pending', 'rejected', 'suspended']) {
      testWidgets('${role.name} $status routes using stored account status', (
        tester,
      ) async {
        final api = FakeApi()
          ..profile = UserModel(uid: 'test', role: role, status: status);
        final controller = AuthController(api: api);
        addTearDown(controller.dispose);
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
            onGenerateRoute: (settings) => MaterialPageRoute(
              settings: settings,
              builder: (_) => Text(settings.name!),
            ),
          ),
        );
        await controller.loginWithEmail(
          context,
          role,
          'test@example.com',
          'password',
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            status == 'active'
                ? AuthController.dashboardRoute(role)
                : Routes.pending,
          ),
          findsOneWidget,
        );
      });
    }
  }
  testWidgets('wrong portal signs out and does not navigate', (tester) async {
    final api = FakeApi();
    final controller = AuthController(api: api);
    addTearDown(controller.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const Text('Login');
          },
        ),
      ),
    );
    await controller.loginWithEmail(
      context,
      UserRole.admin,
      'test@example.com',
      'password',
    );
    expect(api.signedOut, isTrue);
    expect(
      controller.errorMessage,
      'This account does not belong to the selected portal.',
    );
    expect(find.text('Login'), findsOneWidget);
  });
  testWidgets('duplicate login taps result in one request', (tester) async {
    final api = FakeApi()..waitForLogin = Completer<void>();
    final controller = AuthController(api: api);
    addTearDown(controller.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
        onGenerateRoute: (s) =>
            MaterialPageRoute(builder: (_) => const Text('Dashboard')),
      ),
    );
    final first = controller.loginWithEmail(
      context,
      UserRole.citizen,
      'test@example.com',
      'password',
    );
    await controller.loginWithEmail(
      context,
      UserRole.citizen,
      'test@example.com',
      'password',
    );
    expect(api.loginCalls, 1);
    api.waitForLogin!.complete();
    await first;
    await tester.pumpAndSettle();
  });
  testWidgets('protected route removes dashboard when account is suspended', (
    tester,
  ) async {
    final api = SessionApi();
    addTearDown(api.profiles.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authApiProvider.overrideWithValue(api),
          authControllerProvider.overrideWith(
            (ref) => AuthController(api: api),
          ),
        ],
        child: LanguageScope(
          controller: LanguageController(),
          child: MaterialApp(
            home: SessionGate(
              requiredRole: UserRole.admin,
              child: const Text('Protected dashboard'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    api.profiles.add(
      const UserModel(uid: 'test', role: UserRole.admin, status: 'active'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Protected dashboard'), findsOneWidget);
    api.profiles.add(
      const UserModel(uid: 'test', role: UserRole.admin, status: 'suspended'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Protected dashboard'), findsNothing);
    expect(find.textContaining('has been suspended'), findsOneWidget);
  });
  testWidgets(
    'protected route fails closed for missing profile or wrong stored role',
    (tester) async {
      final api = SessionApi();
      addTearDown(api.profiles.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authApiProvider.overrideWithValue(api)],
          child: MaterialApp(
            home: SessionGate(
              requiredRole: UserRole.admin,
              child: const Text('Protected dashboard'),
            ),
          ),
        ),
      );
      await tester.pump();
      api.profiles.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Protected dashboard'), findsNothing);
      api.profiles.add(
        const UserModel(uid: 'test', role: UserRole.citizen, status: 'active'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Protected dashboard'), findsNothing);
      expect(
        find.text('This account does not belong to the selected portal.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('startup restores an active admin to the named admin route', (
    tester,
  ) async {
    final api = SessionApi();
    addTearDown(api.profiles.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authApiProvider.overrideWithValue(api)],
        child: MaterialApp(
          home: SessionGate(restore: true, child: const Text('Welcome')),
          onGenerateRoute: (s) =>
              MaterialPageRoute(builder: (_) => Text(s.name!)),
        ),
      ),
    );
    await tester.pump();
    api.profiles.add(
      const UserModel(uid: 'test', role: UserRole.admin, status: 'active'),
    );
    await tester.pumpAndSettle();
    expect(find.text(Routes.admin), findsOneWidget);
  });
  test(
    'user provider survives listener removal, tracks updates and clears on account switch/logout',
    () async {
      final api = PersistentSessionApi();
      final container = ProviderContainer(
        overrides: [authApiProvider.overrideWithValue(api)],
      );
      addTearDown(api.close);
      addTearDown(container.dispose);
      final subscription = container.listen(currentUserProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      const user = UserModel(
        uid: 'test',
        role: UserRole.citizen,
        fullName: 'Asha',
        status: 'active',
      );
      api.document('test').add(user);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(currentUserProvider)?.fullName, 'Asha');
      subscription.close();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(currentUserProvider), user);
      expect(api.watches, 1);
      api.document('test').add(user.copyWith(status: 'suspended'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(currentUserProvider)?.status, 'suspended');
      api.switchAccount(FakeUser('other'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(currentUserProvider), isNull);
      api.document('test').add(user);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(currentUserProvider), isNull);
      api
          .document('other')
          .add(
            const UserModel(
              uid: 'other',
              role: UserRole.admin,
              status: 'pending',
            ),
          );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(currentUserProvider)?.uid, 'other');
      await api.logout();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(currentUserProvider), isNull);
      expect(container.read(userSessionProvider).isSignedIn, isFalse);
    },
  );
  test(
    'new provider scope restores Firebase session and waits for fresh profile',
    () async {
      final api = PersistentSessionApi();
      addTearDown(api.close);
      final first = ProviderContainer(
        overrides: [authApiProvider.overrideWithValue(api)],
      );
      first.read(userSessionProvider);
      await Future<void>.delayed(Duration.zero);
      api
          .document('test')
          .add(
            const UserModel(
              uid: 'test',
              role: UserRole.citizen,
              status: 'active',
            ),
          );
      await Future<void>.delayed(Duration.zero);
      expect(first.read(currentUserProvider)?.isActive, isTrue);
      first.dispose();
      final restored = ProviderContainer(
        overrides: [authApiProvider.overrideWithValue(api)],
      );
      addTearDown(restored.dispose);
      expect(restored.read(currentUserProvider), isNull);
      await Future<void>.delayed(Duration.zero);
      api
          .document('test')
          .add(
            const UserModel(
              uid: 'test',
              role: UserRole.citizen,
              status: 'suspended',
            ),
          );
      await Future<void>.delayed(Duration.zero);
      expect(restored.read(currentUserProvider)?.status, 'suspended');
      api.document('test').addError(StateError('Connection failed'));
      await Future<void>.delayed(Duration.zero);
      expect(restored.read(currentUserProvider), isNull);
      expect(restored.read(userSessionProvider).state.hasError, isTrue);
    },
  );
  testWidgets(
    'login stores fetched profile and logout clears the shared provider',
    (tester) async {
      final api = PersistentSessionApi();
      addTearDown(api.close);
      final container = ProviderContainer(
        overrides: [authApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      final session = container.read(userSessionProvider);
      final controller = AuthController(api: api, session: session);
      addTearDown(controller.dispose);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
          onGenerateRoute: (s) => MaterialPageRoute(
            builder: (c) {
              context = c;
              return Text(s.name!);
            },
          ),
        ),
      );
      await controller.loginWithEmail(
        context,
        UserRole.citizen,
        'test@example.com',
        'password',
      );
      await tester.pumpAndSettle();
      expect(container.read(currentUserProvider), api.profile);
      await controller.logout(context);
      await tester.pumpAndSettle();
      expect(container.read(currentUserProvider), isNull);
      expect(find.text(Routes.roleSelection), findsOneWidget);
    },
  );
  for (final role in UserRole.values) {
    testWidgets(
      '${role.name} registration fits a small phone and exposes submit action',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWith(
                (ref) => AuthController(api: FakeApi()),
              ),
            ],
            child: LanguageScope(
              controller: LanguageController(),
              child: MaterialApp(home: RegistrationScreen(role: role)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Submit Registration'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('Submit Registration'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Submit Registration'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
