# Build from the repo root:  docker build -f credit-file-service-boot/Dockerfile -t credit-file-service-boot .
# Where Maven Central is blocked: --build-arg MAVEN_MIRROR_URL=https://maven-central.storage-download.googleapis.com/maven2/
# maven:3.9-eclipse-temurin-21 is eclipse-temurin:21-jdk with Maven preinstalled.
FROM maven:3.9-eclipse-temurin-21 AS build
ARG MAVEN_MIRROR_URL=
WORKDIR /src
RUN if [ -n "$MAVEN_MIRROR_URL" ]; then mkdir -p /root/.m2 && printf '%s' \
      "<settings><mirrors><mirror><id>mirror</id><mirrorOf>*</mirrorOf><url>$MAVEN_MIRROR_URL</url></mirror></mirrors></settings>" \
      > /root/.m2/settings.xml; fi
COPY credit-file-service-boot/pom.xml credit-file-service-boot/pom.xml
RUN mvn -B -q -f credit-file-service-boot/pom.xml dependency:go-offline
COPY credit-file-service-boot/src credit-file-service-boot/src
RUN mvn -B -q -f credit-file-service-boot/pom.xml -DskipTests package \
 && java -Djarmode=tools -jar credit-file-service-boot/target/credit-file-service-boot.jar extract --layers --launcher \
        --destination /layers

FROM eclipse-temurin:21-jre
RUN groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid app --home-dir /app app
WORKDIR /app
COPY --from=build /layers/dependencies/ ./
COPY --from=build /layers/spring-boot-loader/ ./
COPY --from=build /layers/snapshot-dependencies/ ./
COPY --from=build /layers/application/ ./
USER 10001:10001
ENV SPRING_PROFILES_ACTIVE=postgres \
    JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError"
EXPOSE 9081
ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
