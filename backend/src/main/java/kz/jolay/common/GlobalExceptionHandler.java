package kz.jolay.common;

import jakarta.validation.ConstraintViolationException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.multipart.MaxUploadSizeExceededException;

import java.util.LinkedHashMap;
import java.util.Map;

@RestControllerAdvice
public class GlobalExceptionHandler {
    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    public record ErrorBody(String code, String message, Map<String, String> fields, String traceId) {}

    private ResponseEntity<ErrorBody> body(HttpStatus s, String code, String msg, Map<String, String> fields) {
        return ResponseEntity.status(s).body(new ErrorBody(code, msg, fields, MDC.get("requestId")));
    }

    @ExceptionHandler(ApiException.class)
    ResponseEntity<ErrorBody> api(ApiException e) { return body(e.status(), e.code(), e.getMessage(), null); }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<ErrorBody> invalid(MethodArgumentNotValidException e) {
        Map<String, String> f = new LinkedHashMap<>();
        e.getBindingResult().getFieldErrors().forEach(x -> f.putIfAbsent(x.getField(), x.getDefaultMessage()));
        return body(HttpStatus.BAD_REQUEST, "validation_failed", "Validation failed", f);
    }

    @ExceptionHandler(ConstraintViolationException.class)
    ResponseEntity<ErrorBody> constraint(ConstraintViolationException e) {
        return body(HttpStatus.BAD_REQUEST, "validation_failed", e.getMessage(), null);
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    ResponseEntity<ErrorBody> unreadable(HttpMessageNotReadableException e) {
        return body(HttpStatus.BAD_REQUEST, "malformed_request", "Malformed request body", null);
    }

    @ExceptionHandler(AccessDeniedException.class)
    ResponseEntity<ErrorBody> denied(AccessDeniedException e) {
        return body(HttpStatus.FORBIDDEN, "forbidden", "Access denied", null);
    }

    @ExceptionHandler(MaxUploadSizeExceededException.class)
    ResponseEntity<ErrorBody> tooLarge(MaxUploadSizeExceededException e) {
        return body(HttpStatus.PAYLOAD_TOO_LARGE, "file_too_large", "File too large", null);
    }

    @ExceptionHandler(DuplicateKeyException.class)
    ResponseEntity<ErrorBody> dup(DuplicateKeyException e) {
        log.warn("duplicate key: {}", e.getMostSpecificCause().getMessage());
        return body(HttpStatus.CONFLICT, "conflict", "Resource already exists or is in a conflicting state", null);
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<ErrorBody> other(Exception e) {
        log.error("unhandled error", e);
        return body(HttpStatus.INTERNAL_SERVER_ERROR, "internal_error", "Unexpected error", null);
    }
}
