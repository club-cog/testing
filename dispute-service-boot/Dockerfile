# syntax=docker/dockerfile:1
# Build context: dispute-service-boot/   (docker build -t dispute-service-boot dispute-service-boot)
FROM eclipse-temurin:21-jdk AS build
ARG MAVEN_VERSION=3.9.9
# Same mirror as local builds; override with --build-arg MAVEN_MIRROR=... if Maven Central is reachable.
ARG MAVEN_MIRROR=https://maven-central.storage-download.googleapis.com/maven2
WORKDIR /build
RUN curl -fsSL "${MAVEN_MIRROR}/org/apache/maven/apache-maven/${MAVEN_VERSION}/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
      | tar -xz -C /opt \
 && mkdir -p /root/.m2 \
 && printf '<settings><mirrors><mirror><id>central-mirror</id><mirrorOf>*</mirrorOf><url>%s</url></mirror></mirrors></settings>' \
      "${MAVEN_MIRROR}" > /root/.m2/settings.xml
ENV PATH=/opt/apache-maven-${MAVEN_VERSION}/bin:$PATH
COPY pom.xml .
RUN mvn -B -q dependency:go-offline
COPY src ./src
RUN mvn -B -q package -DskipTests \
 && cp target/dispute-service-boot-*.jar /build/app.jar \
 && mkdir /build/layers && cd /build/layers && java -Djarmode=layertools -jar /build/app.jar extract

FROM eclipse-temurin:21-jre
RUN groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app
WORKDIR /app
COPY --from=build --chown=app:app /build/layers/dependencies/ ./
COPY --from=build --chown=app:app /build/layers/spring-boot-loader/ ./
COPY --from=build --chown=app:app /build/layers/snapshot-dependencies/ ./
COPY --from=build --chown=app:app /build/layers/application/ ./
USER 10001:10001
ENV SPRING_PROFILES_ACTIVE=postgres \
    JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError"
EXPOSE 9083
ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
