/**
 * Custom error classes for my-cli
 * Provides structured error handling across the application
 */

/**
 * Base error class for all my-cli errors
 */
export class MyCLIError extends Error {
  constructor(message: string) {
    super(message);
    this.name = this.constructor.name;
    Object.setPrototypeOf(this, MyCLIError.prototype);
  }
}

/**
 * Validation error - raised when input validation fails
 * Used for invalid topic names, syntax errors, etc.
 */
export class ValidationError extends MyCLIError {
  constructor(message: string) {
    super(message);
    Object.setPrototypeOf(this, ValidationError.prototype);
  }
}

/**
 * Not found error - raised when a requested resource is not available
 * Used when topic, category, or configuration is not found
 */
export class NotFoundError extends MyCLIError {
  constructor(message: string) {
    super(message);
    Object.setPrototypeOf(this, NotFoundError.prototype);
  }
}

/**
 * Internal error - raised when unexpected runtime errors occur
 * Used for filesystem errors, JSON parsing failures, etc.
 */
export class InternalError extends MyCLIError {
  constructor(message: string) {
    super(message);
    Object.setPrototypeOf(this, InternalError.prototype);
  }
}

/**
 * Security error - raised when security violations are detected
 * Used for injection attempts, unauthorized operations, etc.
 */
export class SecurityError extends MyCLIError {
  constructor(message: string) {
    super(message);
    Object.setPrototypeOf(this, SecurityError.prototype);
  }
}
