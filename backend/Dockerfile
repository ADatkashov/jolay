FROM gradle:9.8-jdk21 AS build
WORKDIR /src
COPY build.gradle settings.gradle ./
COPY gradle ./gradle
COPY src ./src
RUN gradle bootJar -x test --no-daemon

FROM eclipse-temurin:21-jre
RUN useradd -r -u 10001 jolay && mkdir -p /data/documents && chown -R jolay /data
USER jolay
WORKDIR /app
COPY --from=build /src/build/libs/*.jar app.jar
ENV JOLAY_DOCS_DIR=/data/documents SPRING_PROFILES_ACTIVE=prod
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --retries=5 CMD ["sh","-c","wget -qO- http://localhost:8081/actuator/health/readiness 2>/dev/null | grep -q UP || wget -qO- http://localhost:8080/actuator/health/readiness 2>/dev/null | grep -q UP"]
ENTRYPOINT ["java","-XX:MaxRAMPercentage=75","-jar","app.jar"]
