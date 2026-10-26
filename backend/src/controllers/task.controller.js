'use strict';

const { TaskService } = require('../services/task.service');

const service = new TaskService();

/** Lists the authenticated user's tasks. */
async function list(req, res) {
  res.json(await service.list(req.user.id, req.query));
}

/** Creates a task owned by the authenticated user. */
async function create(req, res) {
  const item = await service.create(req.user.id, req.body);
  res.status(201).json({ item });
}

/** Updates one of the authenticated user's tasks. */
async function update(req, res) {
  const item = await service.update(req.user.id, req.params.taskId, req.body);
  res.json({ item });
}

/** Deletes one of the authenticated user's tasks. */
async function remove(req, res) {
  await service.delete(req.user.id, req.params.taskId);
  res.status(204).end();
}

module.exports = { list, create, update, remove };
