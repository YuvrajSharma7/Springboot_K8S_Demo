# ==========================================
# Stage 1: Build the application
# ==========================================
FROM maven:3.9.6-eclipse-temurin-21 AS builder
WORKDIR /app

# Step 1: Copy ONLY the pom.xml first.
# This allows Docker to cache the downloaded dependencies.
# If you only change your source code, Docker won't re-download the internet.
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Step 2: Copy the source code and package the application
COPY src ./src
RUN mvn clean package -DskipTests

# ==========================================
# Stage 2: Create the lightweight runtime image
# ==========================================
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
# LABEL is a metadata instruction that allows you to add information about the image.
# This can be useful for documentation, versioning, or even for tools that read image metadata.
LABEL maintainer="YUVRAJ"
#ENV JAVA_OPTS="-Xmx512m -Xms256m"

# Step 3: Security Best Practice - Create a non-root user
# Running apps as root inside a container is a security risk.
RUN addgroup -S springgroup && adduser -S springuser -G springgroup
USER springuser:springgroup

# Step 4: Copy ONLY the built JAR from the 'builder' stage
# We use a wildcard to grab the jar, renaming it to a standard 'app.jar'
COPY --from=builder /app/target/*.jar app.jar

# Step 5: Expose the port your Spring Boot app runs on
EXPOSE 8080

# Step 6: Define the startup command
ENTRYPOINT ["java", "-jar", "app.jar"]
#ENTRYPOINT /bin/sh -c "java ${JAVA_OPTS} -jar app.jar"
#ENTRYPOINT /bin/sh -c "java -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 --add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.nio=ALL-UNNAMED -jar app.jar"