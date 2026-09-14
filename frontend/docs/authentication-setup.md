# janYukti authentication and registration

The app uses one role-based login screen and one registration screen. Firebase Authentication verifies credentials; `users/{uid}` supplies the authoritative role and account status. Organizations are separate documents linked by `organizationId`.

## Firebase Console configuration

1. Open the Firebase project configured in `lib/firebase_options.dart` (`janyukti-1cbba`). Under Authentication → Sign-in method, enable **Email/Password**.
2. Create the default Cloud Firestore database if it does not exist.
3. Review and publish the repository's complete [Firestore rules](../firestore.rules) before testing registration against production. The old rules did not protect account status. They must not remain deployed with the new client.
4. The Firebase CLI configuration now points to `firestore.rules` and `firestore.indexes.json`. From the project root, an authorized project maintainer can publish them using:

   ```sh
   firebase deploy --only firestore:rules,firestore:indexes --project janyukti-1cbba
   ```

5. Configure Authentication → Templates → Password reset with your desired janYukti sender/action settings. Use an email address with an accessible inbox to test delivery. Add your actual app domains to Authorized domains if using web.
6. Keep the existing Firebase Android/iOS configuration files. No Supabase setup is needed; the unused Supabase dependency has been removed.

No live rules, accounts, or configuration were changed by this implementation. The CLI emulator tests use `demo-janyukti` and cannot target production data.

## Bootstrap administrator

There are no hardcoded or shared admin credentials.

1. In Authentication → Users, add an email/password user with an inbox controlled by your initial administrator. Choose a unique strong password and record the Firebase UID.
2. In Firestore, manually create `users/{thatExactUid}` using the Firebase Console or a trusted Admin SDK. Example:

   ```text
   uid             string     <Firebase Auth UID>
   fullName        string     Initial Administrator
   email           string     <same email as Firebase Auth>
   phone           string     <optional phone>
   role            string     admin
   status          string     active
   organizationId  null       null
   designation     string     Platform Administrator
   createdAt       timestamp  <current time>
   updatedAt       timestamp  <current time>
   ```

3. Select **Admin**, enter those credentials, and open Registration Requests.
4. Create later administrator accounts through **Request Admin Account**. They remain pending until this existing active administrator approves them.

For local QA, use distinct addresses such as `citizen@example.test`, `university@example.test`, `industry@example.test`, and `admin-request@example.test` with passwords you choose. These are examples, not provisioned accounts. Use real inboxes when testing password resets.

## Existing account migration

The former login flow created a profile from whichever portal a user selected. Review existing roles before enabling approval administration; do not automatically approve old admin records.

A missing `status` is treated as pending by the client, never active. Admin pending queries select explicit `status == pending`, so missing-status legacy records must be repaired in the Console first. For verified citizens, set `status: active`. For university, industry, and requested admin accounts, set `status: pending`. Create and link organization records for legacy organization users, including `createdBy` and `type`. Fill required identity fields. Bootstrap an active admin separately after review.

A Firebase Auth account with no Firestore profile cannot access a dashboard or infer its role from the selected portal. Repair the profile through a trusted administrator or remove an incomplete Auth account before retrying registration. Do not modify the installed package cache or use permissive rules to bypass this check.

## Collection structure

```text
users/{firebaseUid}
  uid, fullName, email, phone
  role: citizen | university | industry | admin
  status: active | pending | rejected | suspended
  organizationId: null | organization document ID
  designation, city, state
  createdAt, updatedAt: Firestore timestamps
  approvedBy, approvedAt                  (when approved/reactivated)
  rejectedBy, rejectedAt, rejectionReason (when rejected)
  suspendedBy, suspendedAt                (when suspended)

organizations/{organizationId}
  id, name
  type: university | industry
  organizationCategory                   (university)
  sector                                 (industry)
  officialEmail, phone, website, address, city, state
  status: pending | approved | rejected | suspended
  createdBy: registering Firebase UID
  createdAt, updatedAt
  approval/rejection/suspension audit fields
```

The initial organization registration creates one user and one organization in an atomic batch. The schema supports future membership through `organizationId`; inviting additional organization members is not part of this registration flow. Organization state transitions currently target its registering contact, and any future membership feature must define organization-wide suspension semantics.

Firebase Authentication and Firestore do not share a transaction. If the registration batch fails, the API attempts to delete the newly created Auth account so registration can be retried. If deletion also fails, the user receives recovery instructions and is signed out; an administrator must repair/remove the incomplete account.

## Access and approval behavior

- Citizens register active. University, industry, and admin registrations are pending.
- Wrong-portal login signs out immediately with “This account does not belong to the selected portal.”
- Active accounts navigate with `pushNamedAndRemoveUntil` to the existing role dashboard. Pending/rejected/suspended accounts see their status screen and Logout.
- Startup restores the server profile. Protected named routes watch the profile and remove dashboard access when status changes. Cached approval data does not grant access; account verification requires a server connection.
- Approve requires confirmation. Reject requires a nonempty reason. Actions lock while processing, and transactions reject stale decisions made by another administrator.
- An active administrator can approve pending users, reject pending users, suspend active users, and reactivate suspended users. Suspension/reactivation API methods are available; their management UI was not requested. Rejected registrations are not reactivated by those methods.
- Pending counts, lists, and approved organization counts come from Firestore. Existing challenge/project content still uses the app's existing local `AppStore`; the dashboards were not replaced or migrated.

The rules permit owners to read their profiles and update only personal fields. Owners cannot change role, status, organization links, or audit metadata. Non-citizens cannot create active accounts. Only an existing active administrator can make status decisions for another account. Linked organization decisions must commit together. Other collections remain denied as in the previous rules; add explicit rules when moving the local challenge/project features to Firestore.

The implementation uses Firebase's documented [field allowlists](https://firebase.google.com/docs/firestore/security/rules-fields) and [`getAfter` checks for atomic writes](https://firebase.google.com/docs/firestore/security/rules-conditions).

## Indexes

No composite indexes are required for the current queries. Pending registrations query `users.status == pending`, then filter by role and sort by registration time in Dart. Organization counters query `organizations.status == approved`. Keep automatic single-field indexing enabled on `status` in both collections. `firestore.indexes.json` intentionally has no custom indexes.

For a large deployment, add pagination/server-side filtering and the associated indexes; the current admin view loads the pending set and approved organizations to match this project's size and architecture.

## Automated verification

Verified locally: `flutter analyze` reports no issues; all 27 Flutter tests and all 10 Firestore emulator tests pass. CocoaPods installation succeeds with 23 pods. Native device execution, real email delivery, and live Firebase acceptance flows still require the manual checklist below.

```sh
flutter analyze
flutter test --reporter expanded
npm --prefix tools/firestore-tests ci --ignore-scripts
firebase emulators:exec --config firebase.emulator.json --only firestore \
  --project demo-janyukti 'node --test tools/firestore-tests/rules.test.mjs'
```

The rule tests require Node and Java, and the Firebase CLI downloads the emulator on first use. They test successful registrations as well as denied self-promotion, unauthorized reads, forged approval fields, pending/suspended admin access, non-atomic approval/rejection, and invalid status transitions.

Flutter tests exercise registration validation, all four roles across all statuses, wrong-portal logout, duplicate-request prevention, session restoration/revocation, and registration layouts at 320 × 640.

## Manual acceptance checklist

- [ ] Citizen: required name/email/password, short password and confirmation mismatch show errors; optional location/phone may be empty. Successful registration creates one active citizen and opens CitizenDashboard.
- [ ] University: all organization/contact requirements are enforced; select university type. One pending organization and linked pending user are created; dashboard access is blocked.
- [ ] Industry: select a sector and fill organization/contact details. Verify the same pending flow with `type: industry` and `sector`.
- [ ] Admin request: designation is required; account starts pending and cannot list users or access AdminDashboard.
- [ ] Bootstrap admin: see correct pending count and All/Universities/Industries/Admins filters. Open organization and contact details; verify dates and current status.
- [ ] Approve each of university, industry, and admin: confirmation appears; user becomes active, organization becomes approved where applicable, audit UID/timestamps are correct, and pending item/count update immediately.
- [ ] Login with each approved account: correct role dashboard opens and Back does not return to login. Repeat with the wrong portal and verify immediate logout.
- [ ] Reject a new university/industry/admin request: empty reason is blocked; supplied reason and audit metadata persist. User sees rejection text and never the dashboard.
- [ ] Suspend an active test account through the Admin API/trusted Console; open sessions lose dashboard access. Reactivate a suspended test account and verify access returns.
- [ ] Restart with active, pending, rejected, suspended, missing-profile, and missing-status accounts. No unapproved account gets dashboard access.
- [ ] Forgot Password: invalid email is explained, delivery succeeds for a real inbox, network errors are visible, and duplicate taps are prevented.
- [ ] Network failure during profile load/registration: no dashboard is shown from stale role/status; recovery and Logout work. Confirm failed registration cleanup or follow the recovery message.
- [ ] Test on Android/iOS with keyboard open and larger text; scroll through every form and verify password visibility and loading controls.
- [ ] Existing citizen submissions/tracking, university projects, industry collaboration, and admin challenge review still work.

## Files created or restored

- `lib/apis/auth_api.dart`, `lib/apis/admin_api.dart` — restored the requested API files over their previously removed stubs.
- `lib/models/registration_data.dart`, `lib/models/organization_model.dart`.
- `lib/features/auth/views/registration_screen.dart`, `pending_approval_screen.dart`, `session_gate.dart`.
- `lib/features/auth/widgets/registration_section.dart`, `registration_dropdown.dart`.
- `lib/features/admin/views/registration_approvals_view.dart`, `registration_details_view.dart`.
- `firestore.indexes.json`, `firebase.emulator.json`.
- `test/auth_flow_test.dart`.
- `tools/firestore-tests/package.json`, `package-lock.json`, `.gitignore`, `rules.test.mjs`.
- `docs/authentication-setup.md` (this guide).

## Files modified

- `lib/models/user_model.dart`, `user_role.dart` — profile/status fields and role labels.
- `lib/features/auth/controllers/auth_controller.dart` — authentication, registration, status navigation, reset, logout, loading/errors.
- `lib/features/auth/services/auth_session.dart`, `user_profile_service.dart` — shared logout and removal of role-derived profile creation.
- `lib/features/auth/views/login_screen.dart`, `role_selection_screen.dart` — shared email/password login and registration entry points; display name and analyzer cleanup.
- `lib/features/auth/widgets/auth_text_field.dart`, `auth_header.dart`, `role_card.dart` — form validation and supported color APIs.
- `lib/features/admin/views/admin_views.dart` — Firestore approval preview/counts and organization overview.
- `lib/core/routes/app_routes.dart` — registration, status, approval routes and role guards.
- `lib/main.dart`, `lib/core/localization/app_localizations.dart`, `lib/features/citizen/views/citizen_dashboard.dart`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist` — janYukti display name.
- `lib/widgets/ui.dart` — shared loading button and analyzer cleanup.
- `lib/core/icons/icons.dart`, `lib/core/utils/color_utility.dart`, `lib/theme/app_colors.dart`, `lib/features/citizen/views/add_details_view.dart`, `trach_challange_view.dart` — existing analyzer warnings cleaned up.
- `firestore.rules`, `firebase.json` — authorization and deployment configuration.
- `pubspec.yaml`, `pubspec.lock`, `ios/Podfile.lock`, generated platform plugin registrants — unused Supabase dependency removed and dependencies synchronized; existing Flutter-compatible Firebase pins retained.

## Shared user state

`lib/features/auth/providers/user_provider.dart` now owns the session's user profile. `userSessionProvider` stays alive for the app's `ProviderScope`; navigation does not discard it. Login saves the role-validated Firestore profile before routing, and registration seeds the same provider after creating the profile. A single Firestore subscription keeps every consumer updated. Logout clears the profile, and switching users cancels the previous user's subscription.

Use the current profile in a `ConsumerWidget` or `ConsumerState`:

```dart
final user = ref.watch(currentUserProvider);
Text(user?.fullName ?? '');
```

For loading/error information or an explicit reload:

```dart
final session = ref.watch(userSessionProvider);
final profileState = session.state; // AsyncValue<UserModel?>
ref.read(userSessionProvider).refresh();
```

The citizen greeting and protected route/status checks consume this shared state. Firebase retains the authentication session across app restarts; the provider reloads `users/{uid}` after Firebase restores that session. The in-memory Riverpod object is recreated on restart, and no local approval/role cache grants dashboard access while awaiting server verification. Phone-auth behavior has not been changed by this provider update.
