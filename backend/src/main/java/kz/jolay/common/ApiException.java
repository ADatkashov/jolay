package kz.jolay.common;

import org.springframework.http.HttpStatus;

/** Business error. {@code code} is a stable machine key clients map to localized text. */
public class ApiException extends RuntimeException {
    private final HttpStatus status;
    private final String code;

    public ApiException(HttpStatus status, String code, String message) {
        super(message);
        this.status = status;
        this.code = code;
    }
    public HttpStatus status() { return status; }
    public String code() { return code; }

    public static ApiException badRequest(String code, String msg) { return new ApiException(HttpStatus.BAD_REQUEST, code, msg); }
    public static ApiException notFound(String code, String msg) { return new ApiException(HttpStatus.NOT_FOUND, code, msg); }
    public static ApiException conflict(String code, String msg) { return new ApiException(HttpStatus.CONFLICT, code, msg); }
    public static ApiException forbidden(String code, String msg) { return new ApiException(HttpStatus.FORBIDDEN, code, msg); }
    public static ApiException unauthorized(String code, String msg) { return new ApiException(HttpStatus.UNAUTHORIZED, code, msg); }
    public static ApiException unavailable(String code, String msg) { return new ApiException(HttpStatus.SERVICE_UNAVAILABLE, code, msg); }
    public static ApiException tooMany(String code, String msg) { return new ApiException(HttpStatus.TOO_MANY_REQUESTS, code, msg); }
}
