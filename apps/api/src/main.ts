import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { API_ENVIRONMENT, ApiEnvironment } from './config/environment.js';
import { FARMLY_AUTH, FarmlyAuth } from './auth/auth.module.js';
import { mountFarmlyAuthHandler } from './auth/mount-auth-handler.js';
import { FarmlyHttpExceptionFilter } from './common/farmly-http-exception.filter.js';
import { AppModule } from './app.module.js';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);
  const environment = app.get<ApiEnvironment>(API_ENVIRONMENT);
  const auth = app.get<FarmlyAuth>(FARMLY_AUTH);
  mountFarmlyAuthHandler(app, auth);
  app.useGlobalFilters(new FarmlyHttpExceptionFilter());
  await app.listen(environment.port, '0.0.0.0');
}

void bootstrap();
