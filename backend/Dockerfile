# Multi-stage build so customers need nothing installed but Docker.
#
# Java 25 is the current LTS. See pom.xml for why that version specifically
# matters to this demo.

FROM maven:3.9-eclipse-temurin-25 AS build
WORKDIR /build

# Copy the POM first so dependency resolution is cached across source edits.
# During the demo Copilot will change Java files repeatedly; without this layer
# every rebuild would re-download the world.
COPY pom.xml .
RUN mvn -B -q dependency:go-offline

COPY src ./src
RUN mvn -B -q clean package -DskipTests

FROM eclipse-temurin:25-jre
WORKDIR /app
COPY --from=build /build/target/scaledemo-backend-1.0.0.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
