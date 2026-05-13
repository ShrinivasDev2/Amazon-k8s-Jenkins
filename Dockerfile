FROM maven:3.9-eclipse-temurin-17  AS build
WORKDIR /build

COPY pom.xml .
COPY Amazon-Core/pom.xml Amazon-Core/pom.xml
COPY Amazon-Web/pom.xml Amazon-Web/pom.xml
COPY Amazon-Web Amazon-Web
COPY Amazon-Core Amazon-Core

RUN mvn clean install -pl Amazon-Web -am -DskipTests

#STAGE2

FROM tomcat:9.0

COPY --from=build /build/Amazon-Web/target/*.war /usr/local/tomcat/webapps/ROOT.war

EXPOSE 8080

CMD ["catalina.sh", "run"]