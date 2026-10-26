'use strict';

/**
 * Sends a consistent safe error response.
 *
 * @param {Error} error - Error forwarded by an earlier middleware.
 * @param {import('express').Request} req - Express request.
 * @param {import('express').Response} res - Express response.
 * @param {import('express').NextFunction} _next - Express continuation.
 * @returns {void}
 */
function errorHandler(error, req, res, _next) {
  req.log?.error({ err: error }, 'Request failed');

  if (res.headersSent) return;

  const status = Number.isInteger(error.status) ? error.status : 500;
  const safeStatus = status >= 400 && status < 500 ? status : 500;

  // Malformed JSON bodies get a fixed message instead of the parser's detail.
  if (error.type === 'entity.parse.failed') {
    return res.status(400).json({
      error: { code: 'INVALID_JSON', message: 'The request body is not valid JSON.' },
    });
  }

  res.status(safeStatus).json({
    error: {
      code: safeStatus === 500 ? 'INTERNAL_ERROR' : (error.code || 'REQUEST_ERROR'),
      message: safeStatus === 500 ? 'An unexpected error occurred.' : error.message,
    },
  });
}

module.exports = { errorHandler };
