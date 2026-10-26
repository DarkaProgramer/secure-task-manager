'use strict';

const { z } = require('zod');

/** Validates a new task payload. */
const createTaskSchema = z.object({
  title: z.string().trim().min(1).max(120),
  description: z.string().trim().max(2000).nullable().optional(),
});

/** Validates a partial task update. */
const updateTaskSchema = z.object({
  title: z.string().trim().min(1).max(120).optional(),
  description: z.string().trim().max(2000).nullable().optional(),
  completed: z.boolean().optional(),
}).refine((value) => Object.keys(value).length > 0, {
  message: 'At least one field is required.',
});

/** Validates pagination query parameters. */
const listTasksSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

/** Validates the task identifier in the route path. */
const taskIdParamSchema = z.object({
  taskId: z.string().min(1).max(64).regex(/^[A-Za-z0-9_-]+$/),
});

module.exports = { createTaskSchema, updateTaskSchema, listTasksSchema, taskIdParamSchema };
