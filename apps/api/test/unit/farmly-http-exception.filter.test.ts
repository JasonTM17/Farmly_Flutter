import { HttpException, type ArgumentsHost } from '@nestjs/common';
import { describe, expect, it } from 'vitest';
import { FarmlyHttpExceptionFilter } from '../../src/common/farmly-http-exception.filter.js';

const invitationErrorStatuses = [
  ['INVITATION_NOT_AVAILABLE', 404],
  ['INVITATION_EMAIL_MISMATCH', 403],
  ['INVITATION_EXPIRED', 410],
  ['INVITATION_REVOKED', 410],
  ['INVITATION_ALREADY_ACCEPTED', 409],
  ['MEMBERSHIP_ALREADY_EXISTS', 409],
] as const;

describe('FarmlyHttpExceptionFilter invitation error mapping', () => {
  it.each(invitationErrorStatuses)('%s keeps its documented HTTP status %i', (code, expectedStatus) => {
    const response = {
      statusCode: 0,
      body: undefined as unknown,
      status(statusCode: number) {
        this.statusCode = statusCode;
        return this;
      },
      setHeader() {
        return this;
      },
      json(body: unknown) {
        this.body = body;
      },
    };
    const host = {
      switchToHttp: () => ({ getResponse: () => response }),
    } as unknown as ArgumentsHost;

    new FarmlyHttpExceptionFilter().catch(new HttpException({ code }, expectedStatus), host);

    expect(response.statusCode).toBe(expectedStatus);
    expect(response.body).toMatchObject({ error: { code } });
  });
});
