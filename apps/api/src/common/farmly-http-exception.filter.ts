import { randomUUID } from 'node:crypto';
import { ArgumentsHost, Catch, ExceptionFilter, HttpException } from '@nestjs/common';

interface JsonResponse {
  status(code: number): JsonResponse;
  setHeader(name: string, value: string): JsonResponse;
  json(body: unknown): void;
}

const SAFE_ERRORS: Readonly<Record<number, { code: string; message: string; retryable: boolean }>> = {
  400: { code: 'VALIDATION_FAILED', message: 'The request is invalid.', retryable: false },
  401: { code: 'UNAUTHENTICATED', message: 'Authentication is required.', retryable: false },
  403: { code: 'PERMISSION_DENIED', message: 'The requested action is not allowed.', retryable: false },
  404: { code: 'NOT_FOUND', message: 'The requested resource was not found.', retryable: false },
  409: { code: 'VERSION_CONFLICT', message: 'The request conflicts with current state.', retryable: false },
  410: { code: 'CURSOR_EXPIRED', message: 'The requested resource has expired.', retryable: false },
  422: { code: 'VALIDATION_FAILED', message: 'The request could not be validated.', retryable: false },
  429: { code: 'RATE_LIMITED', message: 'Too many requests.', retryable: true },
  503: { code: 'UPSTREAM_UNAVAILABLE', message: 'The service is temporarily unavailable.', retryable: true },
};

const SAFE_ERROR_OVERRIDES: Readonly<Record<string, { status: number; code: string; message: string; retryable: boolean }>> = {
  ACCESS_REVOKED: { status: 403, code: 'ACCESS_REVOKED', message: 'Access to this organization is no longer available.', retryable: false },
  OPERATION_ID_REUSED: { status: 409, code: 'OPERATION_ID_REUSED', message: 'This operation ID has already been used.', retryable: false },
  INVITATION_NOT_AVAILABLE: { status: 404, code: 'INVITATION_NOT_AVAILABLE', message: 'The invitation is unavailable.', retryable: false },
  INVITATION_EMAIL_MISMATCH: { status: 403, code: 'INVITATION_EMAIL_MISMATCH', message: 'This verified account cannot accept the invitation.', retryable: false },
  INVITATION_EXPIRED: { status: 410, code: 'INVITATION_EXPIRED', message: 'The invitation expired. Ask an organization owner or admin for a new invitation.', retryable: false },
  INVITATION_REVOKED: { status: 410, code: 'INVITATION_REVOKED', message: 'The invitation was revoked. Ask an organization owner or admin for a new invitation.', retryable: false },
  INVITATION_ALREADY_ACCEPTED: { status: 409, code: 'INVITATION_ALREADY_ACCEPTED', message: 'The invitation has already been accepted.', retryable: false },
  MEMBERSHIP_ALREADY_EXISTS: { status: 409, code: 'MEMBERSHIP_ALREADY_EXISTS', message: 'This account already has a membership in the organization.', retryable: false },
  AI_QUOTA_EXCEEDED: { status: 429, code: 'AI_QUOTA_EXCEEDED', message: 'The AI quota for this scope is exhausted. Try again later.', retryable: true },
  AI_REQUEST_MISMATCH: { status: 409, code: 'OPERATION_ID_REUSED', message: 'This request ID has already been used.', retryable: false },
};

@Catch()
export class FarmlyHttpExceptionFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost): void {
    const response = host.switchToHttp().getResponse<JsonResponse>();
    const status = exception instanceof HttpException ? exception.getStatus() : 500;
    const payload = exception instanceof HttpException ? exception.getResponse() : null;
    const payloadCode = payload && typeof payload === 'object' && 'code' in payload && typeof payload.code === 'string'
      ? payload.code
      : null;
    const override = payloadCode ? SAFE_ERROR_OVERRIDES[payloadCode] : undefined;
    const safe = override?.status === status ? override : SAFE_ERRORS[status] ?? {
      code: 'INTERNAL_ERROR', message: 'The request could not be completed.', retryable: status >= 500,
    };
    const requestId = randomUUID();
    response
      .status(status)
      .setHeader('x-request-id', requestId)
      .json({ error: { ...safe, requestId } });
  }
}
