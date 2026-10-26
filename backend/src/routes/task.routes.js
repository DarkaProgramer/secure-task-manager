'use strict';

const express = require('express');
const { requireAuth } = require('../middleware/auth.middleware');
const { validate } = require('../middleware/validate.middleware');
const {
  createTaskSchema,
  updateTaskSchema,
  listTasksSchema,
  taskIdParamSchema,
} = require('../schemas/task.schema');
const { asyncRoute } = require('../utils/async-route');
const controller = require('../controllers/task.controller');

const router = express.Router();

router.use(requireAuth);

router.get('/', validate(listTasksSchema, 'query'), asyncRoute(controller.list));
router.post('/', validate(createTaskSchema, 'body'), asyncRoute(controller.create));
router.patch(
  '/:taskId',
  validate(taskIdParamSchema, 'params'),
  validate(updateTaskSchema, 'body'),
  asyncRoute(controller.update),
);
router.delete('/:taskId', validate(taskIdParamSchema, 'params'), asyncRoute(controller.remove));

module.exports = router;
