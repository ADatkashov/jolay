package kz.jolay.admin;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

/** Creates the first SUPER_ADMIN from environment variables if (and only if) no such account exists. No default password. */
@Component
public class AdminBootstrap implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(AdminBootstrap.class);
    private final JdbcClient jdbc;
    private final PasswordEncoder encoder;
    private final String phone, password, name;

    public AdminBootstrap(JdbcClient jdbc, PasswordEncoder encoder, @Value("${jolay.admin-bootstrap.phone:}") String phone,
                          @Value("${jolay.admin-bootstrap.password:}") String password, @Value("${jolay.admin-bootstrap.name}") String name) {
        this.jdbc = jdbc; this.encoder = encoder; this.phone = phone; this.password = password; this.name = name;
    }

    @Override public void run(ApplicationArguments args) {
        if (phone.isBlank() || password.isBlank()) return;
        if (jdbc.sql("SELECT count(*) FROM user_roles WHERE role='SUPER_ADMIN'").query(Integer.class).single() > 0) return;
        var id = jdbc.sql("INSERT INTO users(phone,password_hash,full_name,phone_verified) VALUES (:p,:h,:n,true) ON CONFLICT DO NOTHING RETURNING id")
                .param("p", phone).param("h", encoder.encode(password)).param("n", name).query(java.util.UUID.class).optional();
        id.ifPresent(u -> { jdbc.sql("INSERT INTO user_roles(user_id,role) VALUES (:u,'SUPER_ADMIN')").param("u", u).update(); log.info("Bootstrap SUPER_ADMIN created"); });
    }
}
