'use strict';

const { request, app, registerUser, bearer, cleanup, disconnect } = require('./helpers');

let alice;
let bob;

beforeAll(async () => {
  alice = await registerUser('alice');
  bob = await registerUser('bob');
});

afterAll(async () => {
  await cleanup();
  await disconnect();
});

const createTask = (user, body) => request(app).post('/api/v1/tasks').set(bearer(user.accessToken)).send(body);

describe('task CRUD for the owner', () => {
  test('creates, lists, updates, and deletes a task', async () => {
    const created = await createTask(alice, { title: '  Write tests  ', description: 'cover everything' });
    expect(created.status).toBe(201);
    expect(created.body.item.title).toBe('Write tests');
    expect(created.body.item.completed).toBe(false);
    const id = created.body.item.id;

    const list = await request(app).get('/api/v1/tasks').set(bearer(alice.accessToken));
    expect(list.status).toBe(200);
    expect(list.body.items.map((t) => t.id)).toContain(id);

    const updated = await request(app).patch(`/api/v1/tasks/${id}`)
      .set(bearer(alice.accessToken)).send({ completed: true });
    expect(updated.status).toBe(200);
    expect(updated.body.item.completed).toBe(true);

    const deleted = await request(app).delete(`/api/v1/tasks/${id}`).set(bearer(alice.accessToken));
    expect(deleted.status).toBe(204);
  });

  test('accepts a null description', async () => {
    const created = await createTask(alice, { title: 'No details', description: null });
    expect(created.status).toBe(201);
    expect(created.body.item.description).toBeNull();
  });
});

describe('ownership (IDOR) checks', () => {
  let aliceTaskId;

  beforeAll(async () => {
    const created = await createTask(alice, { title: 'Alice private task' });
    aliceTaskId = created.body.item.id;
  });

  test("Bob's list never includes Alice's tasks", async () => {
    const list = await request(app).get('/api/v1/tasks').set(bearer(bob.accessToken));
    expect(list.status).toBe(200);
    expect(list.body.items.map((t) => t.id)).not.toContain(aliceTaskId);
  });

  test("Bob cannot update Alice's task", async () => {
    const response = await request(app).patch(`/api/v1/tasks/${aliceTaskId}`)
      .set(bearer(bob.accessToken)).send({ title: 'hacked' });
    expect(response.status).toBe(404);
  });

  test("Bob cannot delete Alice's task", async () => {
    const response = await request(app).delete(`/api/v1/tasks/${aliceTaskId}`).set(bearer(bob.accessToken));
    expect(response.status).toBe(404);
  });

  test("Alice's task is untouched after Bob's attempts", async () => {
    const list = await request(app).get('/api/v1/tasks').set(bearer(alice.accessToken));
    const task = list.body.items.find((t) => t.id === aliceTaskId);
    expect(task.title).toBe('Alice private task');
  });

  test('a client-supplied ownerId is ignored', async () => {
    const created = await createTask(bob, { title: 'Bob task', ownerId: alice.email });
    expect(created.status).toBe(201);
    const aliceList = await request(app).get('/api/v1/tasks?limit=100').set(bearer(alice.accessToken));
    expect(aliceList.body.items.map((t) => t.id)).not.toContain(created.body.item.id);
  });
});

describe('validation and pagination', () => {
  test('rejects an empty title and an empty update', async () => {
    expect((await createTask(alice, { title: '   ' })).status).toBe(400);
    const created = await createTask(alice, { title: 'x' });
    const empty = await request(app).patch(`/api/v1/tasks/${created.body.item.id}`)
      .set(bearer(alice.accessToken)).send({});
    expect(empty.status).toBe(400);
  });

  test('rejects malformed task ids without leaking details', async () => {
    const response = await request(app).patch('/api/v1/tasks/' + encodeURIComponent("1'; DROP TABLE \"Task\";--"))
      .set(bearer(alice.accessToken)).send({ title: 'x' });
    expect(response.status).toBe(400);
    expect(JSON.stringify(response.body)).not.toMatch(/prisma|sql|stack/i);
  });

  test('enforces pagination bounds', async () => {
    const tooBig = await request(app).get('/api/v1/tasks?limit=101').set(bearer(alice.accessToken));
    expect(tooBig.status).toBe(400);
    const badPage = await request(app).get('/api/v1/tasks?page=0').set(bearer(alice.accessToken));
    expect(badPage.status).toBe(400);
  });

  test('paginates results without overlap', async () => {
    const carol = await registerUser('carol');
    for (let i = 0; i < 5; i += 1) await createTask(carol, { title: `task ${i}` });
    const first = await request(app).get('/api/v1/tasks?page=1&limit=2').set(bearer(carol.accessToken));
    const second = await request(app).get('/api/v1/tasks?page=2&limit=2').set(bearer(carol.accessToken));
    const third = await request(app).get('/api/v1/tasks?page=3&limit=2').set(bearer(carol.accessToken));
    const ids = [...first.body.items, ...second.body.items, ...third.body.items].map((t) => t.id);
    expect(first.body.items).toHaveLength(2);
    expect(third.body.items).toHaveLength(1);
    expect(new Set(ids).size).toBe(5);
  });

  test('a missing task returns the generic not-found error', async () => {
    const response = await request(app).delete('/api/v1/tasks/doesnotexist123').set(bearer(alice.accessToken));
    expect(response.status).toBe(404);
    expect(response.body.error.code).toBe('NOT_FOUND');
  });
});
