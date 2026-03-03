FROM gradle:8.14-jdk21 AS build

WORKDIR /app

# Copy Gradle configuration first for better layer caching
COPY gradle/ gradle/
COPY gradlew .
COPY gradlew.bat .
COPY build.gradle.kts .
COPY settings.gradle.kts .
COPY gradle.properties .

# Copy backend module
COPY backend/build.gradle.kts backend/

# Download dependencies (cached layer)
RUN gradle :backend:dependencies --no-daemon || true

# Copy backend source code
COPY backend/src/ backend/src/

# Build the fat JAR
RUN gradle :backend:buildFatJar --no-daemon

# --- Runtime stage ---
FROM eclipse-temurin:21-jre-alpine AS runtime

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

COPY --from=build /app/backend/build/libs/pushup-backend.jar ./pushup-backend.jar

RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 8080

ENV PORT=8080
ENV HOST=0.0.0.0

ENTRYPOINT ["java", "-jar", "pushup-backend.jar"]
