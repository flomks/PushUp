FROM gradle:8.14-jdk21 AS build

WORKDIR /app

# Copy Gradle configuration first for better layer caching
COPY gradle/ gradle/
COPY gradlew .
COPY gradlew.bat .
COPY build.gradle.kts .
COPY settings.gradle.kts .
COPY gradle.properties .

# Copy backend module build file for dependency caching
COPY backend/build.gradle.kts backend/

# Download dependencies (cached layer)
RUN gradle :backend:dependencies --no-daemon 2>/dev/null; exit 0

# Copy backend source code
COPY backend/src/ backend/src/

# Build the fat JAR
RUN gradle :backend:buildFatJar --no-daemon

# --- Runtime stage ---
FROM eclipse-temurin:21-jre-alpine AS runtime

RUN addgroup -S appgroup && adduser -S appuser -G appgroup && \
    apk add --no-cache wget

WORKDIR /app

COPY --from=build /app/backend/build/libs/pushup-backend.jar ./pushup-backend.jar

RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 8080

ENV PORT=8080
ENV HOST=0.0.0.0
ENV KTOR_ENV=production

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

ENTRYPOINT ["java", \
    "-XX:+UseContainerSupport", \
    "-XX:MaxRAMPercentage=75.0", \
    "-XX:+UseG1GC", \
    "-jar", "pushup-backend.jar"]
