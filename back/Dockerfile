# MicroCRM API (Spring Boot). Multi-stage: the JDK and Gradle stay in the build stage,
# the final image only holds a Java 17 runtime and the application JAR.
# Containerization plan: docs/documentation-technique.md, section 3.1.

# ---- Build stage ----
FROM eclipse-temurin:17.0.21.1_2-jdk-alpine AS build
WORKDIR /src

# Gradle wrapper and build files first: the dependency layer stays cached until they change
COPY gradlew settings.gradle build.gradle gradle.lockfile ./
COPY gradle ./gradle
RUN ./gradlew dependencies --no-daemon > /dev/null

# Then the sources. Tests run in CI, not during the image build.
COPY src ./src
RUN ./gradlew bootJar --no-daemon

# ---- Runtime stage ----
FROM eclipse-temurin:17.0.21.1_2-jre-alpine

# Unprivileged user: the application never runs as root
RUN addgroup -S app && adduser -S -G app app \
    && mkdir /data && chown app:app /data # database files (volume microcrm-data)
WORKDIR /app
COPY --from=build /src/build/libs/microcrm-*.jar /app/app.jar
USER app

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
