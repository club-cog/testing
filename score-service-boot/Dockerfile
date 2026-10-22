# Build from the repo root (shared-db is a build dependency):
#   docker build -f score-service-boot/Dockerfile -t score-service-boot:dev .
# MAVEN_MIRROR_URL optionally points Maven at an internal mirror of Maven Central.
FROM maven:3.9-eclipse-temurin-21 AS build
ARG MAVEN_MIRROR_URL=
WORKDIR /src
RUN if [ -n "$MAVEN_MIRROR_URL" ]; then mkdir -p /root/.m2 && printf '%s' \
      "<settings><mirrors><mirror><id>mirror</id><mirrorOf>*</mirrorOf><url>${MAVEN_MIRROR_URL}</url></mirror></mirrors></settings>" \
      > /root/.m2/settings.xml; fi
COPY pom.xml .
COPY shared-db shared-db
COPY score-service-boot score-service-boot
RUN mvn -B -q -N install \
 && mvn -B -q -f shared-db/pom.xml install -DskipTests \
 && mvn -B -q -f score-service-boot/pom.xml package -DskipTests \
 && cp score-service-boot/target/score-service-boot-*.jar /app.jar \
 && mkdir /layers && cd /layers && java -Djarmode=layertools -jar /app.jar extract

FROM eclipse-temurin:21-jre
RUN groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid app --no-create-home app
WORKDIR /app
COPY --from=build /layers/dependencies/ ./
COPY --from=build /layers/spring-boot-loader/ ./
COPY --from=build /layers/snapshot-dependencies/ ./
COPY --from=build /layers/application/ ./
USER 10001:10001
ENV PORT=9082 \
    SPRING_PROFILES_ACTIVE=postgres \
    JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError"
EXPOSE 9082
ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
