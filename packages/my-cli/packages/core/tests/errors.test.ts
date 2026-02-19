/**
 * Unit tests for error classes
 * CL-1.2: Error classes and exit codes
 */

import { describe, it, expect } from 'vitest';
import {
  ValidationError,
  NotFoundError,
  InternalError,
  SecurityError,
  MyCLIError,
} from '../src/errors';
import { ExitCode, getExitCode, getExitMessage } from '../src/exit-codes';

describe('Error Classes', () => {
  describe('ValidationError', () => {
    it('should create a ValidationError instance', () => {
      const error = new ValidationError('Invalid topic name');
      expect(error).toBeInstanceOf(ValidationError);
      expect(error).toBeInstanceOf(MyCLIError);
      expect(error).toBeInstanceOf(Error);
    });

    it('should have correct error message', () => {
      const message = 'Invalid topic name';
      const error = new ValidationError(message);
      expect(error.message).toBe(message);
    });

    it('should have correct error name', () => {
      const error = new ValidationError('test');
      expect(error.name).toBe('ValidationError');
    });
  });

  describe('NotFoundError', () => {
    it('should create a NotFoundError instance', () => {
      const error = new NotFoundError('Topic not found');
      expect(error).toBeInstanceOf(NotFoundError);
      expect(error).toBeInstanceOf(MyCLIError);
      expect(error).toBeInstanceOf(Error);
    });

    it('should have correct error message', () => {
      const message = 'Topic not found';
      const error = new NotFoundError(message);
      expect(error.message).toBe(message);
    });

    it('should have correct error name', () => {
      const error = new NotFoundError('test');
      expect(error.name).toBe('NotFoundError');
    });
  });

  describe('InternalError', () => {
    it('should create an InternalError instance', () => {
      const error = new InternalError('Unexpected error');
      expect(error).toBeInstanceOf(InternalError);
      expect(error).toBeInstanceOf(MyCLIError);
      expect(error).toBeInstanceOf(Error);
    });

    it('should have correct error message', () => {
      const message = 'File read failed';
      const error = new InternalError(message);
      expect(error.message).toBe(message);
    });

    it('should have correct error name', () => {
      const error = new InternalError('test');
      expect(error.name).toBe('InternalError');
    });
  });

  describe('SecurityError', () => {
    it('should create a SecurityError instance', () => {
      const error = new SecurityError('Injection attempt detected');
      expect(error).toBeInstanceOf(SecurityError);
      expect(error).toBeInstanceOf(MyCLIError);
      expect(error).toBeInstanceOf(Error);
    });

    it('should have correct error message', () => {
      const message = 'Injection attempt detected';
      const error = new SecurityError(message);
      expect(error.message).toBe(message);
    });

    it('should have correct error name', () => {
      const error = new SecurityError('test');
      expect(error.name).toBe('SecurityError');
    });
  });

  describe('Error message preservation', () => {
    it('should preserve complex error messages', () => {
      const complexMessage = 'Invalid character ";" found in topic name at position 5';
      const error = new ValidationError(complexMessage);
      expect(error.message).toBe(complexMessage);
    });
  });
});

describe('Exit Codes', () => {
  describe('ExitCode enum', () => {
    it('should have correct exit code values', () => {
      expect(ExitCode.Success).toBe(0);
      expect(ExitCode.InvalidInput).toBe(1);
      expect(ExitCode.UsageError).toBe(2);
      expect(ExitCode.InternalError).toBe(3);
      expect(ExitCode.SecurityError).toBe(4);
    });
  });

  describe('getExitCode function', () => {
    it('should return InvalidInput for ValidationError', () => {
      const error = new ValidationError('test');
      expect(getExitCode(error)).toBe(ExitCode.InvalidInput);
    });

    it('should return InvalidInput for NotFoundError', () => {
      const error = new NotFoundError('test');
      expect(getExitCode(error)).toBe(ExitCode.InvalidInput);
    });

    it('should return InternalError for InternalError', () => {
      const error = new InternalError('test');
      expect(getExitCode(error)).toBe(ExitCode.InternalError);
    });

    it('should return SecurityError for SecurityError', () => {
      const error = new SecurityError('test');
      expect(getExitCode(error)).toBe(ExitCode.SecurityError);
    });

    it('should return InternalError for unknown error types', () => {
      const error = new Error('Unknown error');
      expect(getExitCode(error)).toBe(ExitCode.InternalError);
    });
  });

  describe('getExitMessage function', () => {
    it('should return empty string for Success', () => {
      expect(getExitMessage(ExitCode.Success)).toBe('');
    });

    it('should return appropriate message for InvalidInput', () => {
      expect(getExitMessage(ExitCode.InvalidInput)).toBe('Invalid input provided');
    });

    it('should return appropriate message for UsageError', () => {
      expect(getExitMessage(ExitCode.UsageError)).toBe('Usage error');
    });

    it('should return appropriate message for InternalError', () => {
      expect(getExitMessage(ExitCode.InternalError)).toBe('Internal error occurred');
    });

    it('should return appropriate message for SecurityError', () => {
      expect(getExitMessage(ExitCode.SecurityError)).toBe('Security error detected');
    });
  });
});
