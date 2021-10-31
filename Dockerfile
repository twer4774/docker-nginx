#FROM openjdk:11.0.12-jre-slim-buster as BUILD_IMAGE
#
#ENV APP_HOME=/usr/app/
#
## 작업 폴더 위치
#WORKDIR $APP_HOME
#
## 필수 파일 복사
#COPY gradlew $APP_HOME
#COPY build.gradle $APP_HOME
#COPY settings.gradle $APP_HOME
#COPY gradle $APP_HOME/gradle
#
#RUN ./gradlew -x test build || return 0
#
## 프로젝트 소스 폴더 복사
#COPY src src
#
## gradlew 빌드
##RUN ./gradlew bootjar
#RUN ./gradlew clean build
#
## Dcoker 이미지 실행
#FROM openjdk:11.0.12-jre-slim-buster
#ENV TZ Asia/Seoul
#ENV APP_HOME=/usr/app/
#WORKDIR $APP_HOME
#
## jar 파일 복사
#COPY --from=BUILD_IMAGE $APP_HOME/build/libs/*.jar app.jar
#
#EXPOSE 8080
#
##COPY /build/libs/*-SNAPSHOT.jar app.jar
#ENTRYPOINT ["java", "-jar", "app.jar"]

FROM openjdk:11
EXPOSE : 8080
ARG JAR_FILE=build/libs/*.jar
COPY ${JAR_FILE} app.jar
ENTRYPOINT ["java", "-jar", "app.jar"]