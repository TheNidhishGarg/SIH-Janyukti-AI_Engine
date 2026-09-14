import { before, after, beforeEach, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, getDoc, getDocs, collection, query, where, writeBatch, serverTimestamp } from 'firebase/firestore';
let env;
before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-janyukti', firestore: {host: '127.0.0.1', port: 8088, rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8')}});
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });
const db = uid => env.authenticatedContext(uid, {email: `${uid}@example.test`}).firestore();
const profile = (uid, role, status = role === 'citizen' ? 'active' : 'pending', org = null) => ({
  uid, fullName: 'Test User', email: `${uid}@example.test`, phone: '9876543210', role, status,
  organizationId: org, designation: 'Coordinator', city: 'Delhi', state: 'Delhi', createdAt: serverTimestamp(), updatedAt: serverTimestamp()
});
const organization = (uid, id, type) => ({id, name: 'Test Organization', type,
  ...(type === 'university' ? {organizationCategory: 'State University'} : {sector: 'Information Technology'}),
  officialEmail: `${uid}@example.test`, phone: '9876543210', address: 'Test Address', city: 'Delhi', state: 'Delhi',
  status: 'pending', createdBy: uid, createdAt: serverTimestamp(), updatedAt: serverTimestamp()
});
async function seed(uid, role, status) {
  await env.withSecurityRulesDisabled(async ctx => setDoc(doc(ctx.firestore(), 'users', uid), profile(uid, role, status)));
}
async function registerOrg(uid, role) {
  const database = db(uid); const batch = writeBatch(database);
  batch.set(doc(database, 'users', uid), profile(uid, role, 'pending', uid));
  batch.set(doc(database, 'organizations', uid), organization(uid, uid, role));
  return batch.commit();
}
function decision(database, uid, status, withOrg = true, reason = 'Incomplete documents') {
  const actor = 'root'; const batch = writeBatch(database);
  const audit = {updatedAt: serverTimestamp(), ...(status === 'active' ? {approvedBy: actor, approvedAt: serverTimestamp()} : status === 'rejected' ? {rejectedBy: actor, rejectedAt: serverTimestamp(), rejectionReason: reason} : {suspendedBy: actor, suspendedAt: serverTimestamp()})};
  batch.update(doc(database, 'users', uid), {status, ...audit});
  if (withOrg) batch.update(doc(database, 'organizations', uid), {status: status === 'active' ? 'approved' : status, ...audit});
  return batch.commit();
}
test('citizen registers active and reads only their own profile', async () => {
  await assertSucceeds(setDoc(doc(db('citizen'), 'users', 'citizen'), profile('citizen', 'citizen')));
  await assertSucceeds(getDoc(doc(db('citizen'), 'users', 'citizen')));
  await assertFails(getDoc(doc(db('other'), 'users', 'citizen')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'users', 'citizen')));
});
test('admin registration is pending and cannot self-promote or forge audits', async () => {
  await assertFails(setDoc(doc(db('admin'), 'users', 'admin'), profile('admin', 'admin', 'active')));
  await assertFails(setDoc(doc(db('admin'), 'users', 'admin'), {...profile('admin', 'admin'), approvedBy: 'admin'}));
  await assertSucceeds(setDoc(doc(db('admin'), 'users', 'admin'), profile('admin', 'admin')));
  await assertFails(updateDoc(doc(db('admin'), 'users', 'admin'), {status: 'active', updatedAt: serverTimestamp()}));
  await assertFails(getDocs(query(collection(db('admin'), 'users'), where('status', '==', 'pending'))));
});
test('citizen cannot change role, status, organization, or approval metadata', async () => {
  await seed('citizen', 'citizen', 'active');
  for (const patch of [{role: 'admin'}, {status: 'pending'}, {organizationId: 'hijacked'}, {approvedBy: 'citizen'}]) {
    await assertFails(updateDoc(doc(db('citizen'), 'users', 'citizen'), {...patch, updatedAt: serverTimestamp()}));
  }
  await assertSucceeds(updateDoc(doc(db('citizen'), 'users', 'citizen'), {fullName: 'Updated Name', updatedAt: serverTimestamp()}));
});
for (const role of ['university', 'industry']) {
  test(`${role} must create linked pending documents atomically`, async () => {
    await assertFails(setDoc(doc(db(role), 'users', role), profile(role, role, 'pending', role)));
    await assertFails(setDoc(doc(db(role), 'organizations', role), organization(role, role, role)));
    await assertSucceeds(registerOrg(role, role));
    await assertSucceeds(getDoc(doc(db(role), 'organizations', role)));
    await assertFails(getDoc(doc(db('outsider'), 'organizations', role)));
    await assertFails(updateDoc(doc(db(role), 'organizations', role), {status: 'approved', updatedAt: serverTimestamp()}));
    await assertFails(decision(db(role), role, 'active'));
  });
  test(`approved admin must approve both ${role} documents together`, async () => {
    await seed('root', 'admin', 'active'); await registerOrg(role, role);
    await assertFails(decision(db('root'), role, 'active', false));
    await assertSucceeds(decision(db('root'), role, 'active'));
    await assertFails(decision(db('root'), role, 'active'));
    await assertSucceeds(decision(db('root'), role, 'suspended'));
    await assertSucceeds(decision(db('root'), role, 'active'));
  });
}
test('only active admin may approve another admin', async () => {
  await seed('root', 'admin', 'pending'); await seed('candidate', 'admin', 'pending');
  await assertFails(decision(db('root'), 'candidate', 'active', false));
  await seed('root', 'admin', 'active');
  await assertSucceeds(decision(db('root'), 'candidate', 'active', false));
  await assertSucceeds(getDocs(query(collection(db('root'), 'users'), where('status', '==', 'pending'))));
  await seed('root', 'admin', 'suspended');
  await assertFails(getDocs(collection(db('root'), 'users')));
});
test('rejection requires reason and updates both records', async () => {
  await seed('root', 'admin', 'active'); await registerOrg('university', 'university');
  await assertFails(decision(db('root'), 'university', 'rejected', true, ''));
  await assertFails(decision(db('root'), 'university', 'rejected', true, ' \n\t '));
  await assertFails(decision(db('root'), 'university', 'rejected', false));
  await assertSucceeds(decision(db('root'), 'university', 'rejected', true, 'Incomplete documents\nPlease contact support.'));
  await assertFails(decision(db('root'), 'university', 'active'));
});
test('admin cannot alter target role or forge approver identity', async () => {
  await seed('root', 'admin', 'active'); await seed('candidate', 'admin', 'pending');
  await assertFails(updateDoc(doc(db('root'), 'users', 'candidate'), {role: 'citizen', status: 'active', approvedBy: 'root', approvedAt: serverTimestamp(), updatedAt: serverTimestamp()}));
  await assertFails(updateDoc(doc(db('root'), 'users', 'candidate'), {status: 'active', approvedBy: 'candidate', approvedAt: serverTimestamp(), updatedAt: serverTimestamp()}));
});
