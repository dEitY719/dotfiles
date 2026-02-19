/**
 * Exit codes for my-cli
 * Follows Unix convention: 0 = success, 1-255 = various errors
 */

export enum ExitCode {
  Success = 0,
  InvalidInput = 1,
  UsageError = 2,
  InternalError = 3,
  SecurityError = 4,
}

/**
 * Maps error types to appropriate exit codes
 */
export function getExitCode(error: Error): ExitCode {
  if (error.name === 'ValidationError') {
    return ExitCode.InvalidInput;
  }
  if (error.name === 'NotFoundError') {
    return ExitCode.InvalidInput;
  }
  if (error.name === 'SecurityError') {
    return ExitCode.SecurityError;
  }
  // Default to internal error for unknown error types
  return ExitCode.InternalError;
}

/**
 * Maps exit codes to error messages
 */
export function getExitMessage(code: ExitCode): string {
  switch (code) {
    case ExitCode.Success:
      return '';
    case ExitCode.InvalidInput:
      return 'Invalid input provided';
    case ExitCode.UsageError:
      return 'Usage error';
    case ExitCode.InternalError:
      return 'Internal error occurred';
    case ExitCode.SecurityError:
      return 'Security error detected';
    default:
      return 'Unknown error';
  }
}
