# Spring boot 무중단 배포 정리

- Docker-compose
- jenkins
- nginx
- spring boot

## 목표

- Spring Boot Application 작성

- Nginx를 이용해 무중단 배포

  - Nginx Docker로 시작하기

- Jenkins과 Github 연결 후 push로 배포하기

  - Jenkins과 Github 연결
  - 배포 스크립트 작성

  

## 무중단 배포

- 무중단 배포 방법: Proxy_pass를 배포 시점마다 바꾸고, nginx reload
  - nginx reload의 실행시간은 1초 정도로 매우 짧다
- **nginx의 upstream server를 이용해서 무중단 배포인 척 하는 방법** (여기서 정리한 내용)
  - upstream server :  Origin 서버라고도 불리며, 여러대의 컴퓨터가 어떤 서비스를 순차적으로 일을 처리할 때 사용되는 서버

## Spring Boot Application 작성

### Spring Boot Application

- build.gradle

```groovy
plugins {
	id 'org.springframework.boot' version '2.5.6'
	id 'io.spring.dependency-management' version '1.0.11.RELEASE'
	id 'java'
}

group = 'walter.unit'
version = '0.0.1-SNAPSHOT'
sourceCompatibility = '11'

repositories {
	mavenCentral()
}

dependencies {
	implementation 'org.springframework.boot:spring-boot-starter-web'

	implementation 'org.springframework.boot:spring-boot-starter-actuator'

	compileOnly 'org.projectlombok:lombok'
	annotationProcessor 'org.springframework.boot:spring-boot-configuration-processor'
	annotationProcessor 'org.projectlombok:lombok'
	testCompileOnly 'org.projectlombok:lombok' // 테스트 의존성 추가
	testAnnotationProcessor 'org.projectlombok:lombok' // 테스트 의존성 추가

	testImplementation 'org.springframework.boot:spring-boot-starter-test'
}

test {
	useJUnitPlatform()
}

```

- controller: IndexController

```java
@RequiredArgsConstructor
@RestController
public class IndexController {

    @Value("${index.string}")
    private String indexString;

    @GetMapping("/index")
    public ResponseEntity<String> index(){
        return ResponseEntity.ok().body(indexString);
    }



}
```

- application.yml

  ```yaml
  spring:
  
    profiles:
      group:
        "blue" : "blue"
        "green" : "green"
      default: "blue"
  
    datasource:
      url: jdbc:mysql://test_db
      username: root
      password: root
      driver-class-name: com.mysql.jdbc.Driver
  ---
  spring:
    config:
      activate:
        on-profile: "blue"
  
  ---
  spring:
    config:
      activate:
        on-profile: "green"
  ```

- application-blue.yml

```yaml
server:
  port: 8081

index:
  string: "index-blue"
```

- application-green.yml

```yaml
server:
  port: 8082

index:
  string: "index-green"
```

### Spring Boot Application Docker-compose로 실행

- docker-compose.blue.yml

```dockerfile
version: '3'

services:
  app:
    image: app:0.1
    container_name: app_blue
    environment:
      - "spring_profiles_active=blue"
    ports:
      - "8081:8081"
```

- docker-compose.green.yml

```dockerfile
version: '3'

services:
  app:
    image: app:0.2
    container_name: app_green
    environment:
      - "spring_profiles_active=green"
    ports:
      - "8082:8082"
```

## Nginx Docker로 시작하기

### nginx-Dockerfile : dockerization을 위한 dockerfile

```dockerfile
FROM nginx:1.11

RUN rm -rf /etc/nginx/conf.d/default.conf

COPY ./conf.d/app.conf /etc/nginx/conf.d/app.conf
COPY ./conf.d/nginx.conf /etc/nginx/nginx.conf

VOLUME ["/data", "/etc/nginx", "/var/log/nginx"]

WORKDIR /etc/nginx

CMD ["nginx"]

EXPOSE 80
```

### conf.d/app.conf

- nginx.conf에서 upstream로 설정된 docker-app의 url 매핑

```
server {
    listen 80;
    listen [::]:80;

    server_name "";

    access_log off;

    location / {
        proxy_pass http://docker-app;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto http;
        proxy_max_temp_file_size 0;

        proxy_connect_timeout 150;
        proxy_send_timeout 100;
        proxy_read_timeout 100;

        proxy_buffer_size 8k;
        proxy_buffers 4 32k;
        proxy_busy_buffers_size 64k;
        proxy_temp_file_write_size 64k;
    }
}
```

### conf.d/nginx.conf

- upstream에 설정된 url을 Round Robin 방식으로 순환하며 호출

```
daemon off;
user www-data;
worker_processes 2;

error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    accept_mutex off;
}

http {
    include /etc/nginx/mime.types;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

    default_type application/octet-stream;

    upstream docker-app {
        least_conn;
        server 172.17.0.1:8081 weight=10 max_fails=3 fail_timeout=30s;
        server 172.17.0.1:8082 weight=10 max_fails=3 fail_timeout=30s;
    }

    log_format main '$remote_addr - $remote_user [$time_local] "$request"'
    '$status $body_bytes_sent "$http_referer"'
    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    #tcp_nopush

    keepalive_timeout 65;

    client_max_body_size 300m;
    client_body_buffer_size 128k;

    gzip on;
    gzip_http_version 1.0;
    gzip_comp_level 6;
    gzip_min_length 0;
    gzip_buffers 16 8k;
    gzip_proxied any;
    gzip_types text/plain text/css text/xml text/javascript application/xml application/xml+rss application/javascript application/json;
    gzip_disable "MSIE [1-6]\.";
    gzip_vary on;

    #리눅스환경에서 취급하는 호스팅하는 웹서버 경로
    include /etc/nginx/conf.d/*.conf;

}
```

- nginx 실행(선택 사항1)

```
docker build -t docker-nginx:0.1 -f nginx-Dockerfile .

docker run -d --name docker-nginx -p 80:80 docker-nginx:0.1
```

- docker-compose로 실행하는 경우(선택 사항2)

```
version: '3'

services:
  proxy:
    image: docker-nginx:0.1
    container_name: proxy
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf.d
    environment:
      TZ: Asia/Seoul
```

## Jenkins과 Github 연결

### jenkins docker로 실행하기

- jenkins-Dockerfile

```dockerfile
FROM jenkins/jenkins:jdk11

#도커를 실행하기 위한 root 계정으로 전환
USER root

#도커 설치
COPY docker_install.sh /docker_install.sh
RUN chmod +x /docker_install.sh
RUN /docker_install.sh

#설치 후 도커그룹의 jenkins 계정 생성 후 해당 계정으로 변경
RUN groupadd -f docker
RUN usermod -aG docker jenkins
USER jenkins
```

- docker_install.sh

```
#!/bin/sh -li
apt-get update && \
apt-get -y install apt-transport-https \
  ca-certificates \
  curl \
  gnupg2 \
  zip \
  unzip \
  software-properties-common && \
curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg > /tmp/dkey; apt-key add /tmp/dkey && \
add-apt-repository \
"deb [arch=amd64] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
$(lsb_release -cs) \
stable" && \
apt-get update && \
apt-get -y install docker-ce
```

- 실행

```
docker image build -t docker-jenkins:0.1 -f jenkins-Dockerfile .

docker run --name docker-nginx-jenkins -itd 
    -e JENKINS_USER=$(id -u) \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v $(pwd)/jenkins_home:/var/jenkins_home \
    -p 8080:8080 -p 5000:5000 \
    -u root \
		docker-jenkins:0.1
```

### Jenkins 설정(초기 비밀번호 필요)

- localhost:8080 으로 접속하면 위에서 제시된 초기 비밀번호를 넣는 화면이 나온다.
- install suggested plugins으로 설치
  - 계정명, 암호, 접속 URL등 설정

### Github 연결

#### 프로젝트 생성 - 새로운 item (기본 버전)

- Project 이름을 넣고, Freestyle project로 선택 

- 소스 코드 관리 - Git

- 만약, git push했을 때 자동으로 build되도록 하려면 아래의 WebHook으로 jenkins연동하기 이용

- git repository URL

- Build - Execute shell

  - 각각 Execute shell로 입력

  ```
  ./gradlew clean build
  
  docker build -t app1:0.1 .
  
  docker ps -q --filter "name=app1" || grep -q . && docker stop app1 && docker rm app1 || true
  
  docker run -p 8081:8081 -d --name=app1 app1:0.1
  
  #dangling=true : 불필요한 이미지 지우기
  docker rmi -f $(docker images -f "dangling=true" -q) || true
  ```

#### 실행

- Build Now

#### jenkins github 연동하기 방법 1(github integration plugin)

https://nirsa.tistory.com/301

- github integration plugin 설치

#### jenkins github 연동하기 방법 2(webhook)

https://pooney.tistory.com/86

- WebHook : 이벤트가 발생하면 지정된 URL로 이벤트를 발행한다.

- github - setting - Developer Settings - Personal access tokens - generate new token

  - repo, adminrepo_hook

- 젠킨스에서 키값 생성

  ```
  #key 생성
  ssh-keygen
  
  #key확인. 출력되는 값 복사('젠킨스 키'라고 명명)
  cat ~/.ssh/id_rsa.pub
  
  ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDKnBeEvxdyNABgpqayo1Owjy7jdYOoi5uIGNczO/047jHtZiYm1wEBl/SAt9r9Nh9LmSWC8cwsPKy0DZu2fPdrLgjz86CTh//CL1qmCQbbChH9J5biaL9uMCntc9UORMWPa+kVSLRYfpK7bI98b4JblR8IJcvVzefen6uXkZpwWwajOgwJVG0N5...
  ```

- github - repository - settings - webhooks - Add webhook

  - docker inspect docker-nginx-jenkins
  - Payload URL : http://121.161.1xx.x:8080/github-webhook/
    - 로컬 컴퓨터라면 포트포워딩 필요

- github - repository - settings - Deply keys - Add deply key

  - Title 이름 지정, key는 '젠킨스 키'값 입력

- Jenkins - Add Credentials - SSH Username with private key

  - ID : 키 등록시 사용할 이름
  - Username : Github Profile 이름(twer4774)
  - private key : 젠킨스 key '젠킨스 키' 값 입력
  - 빌드유발 : Gihub hook trigger for GITScm polling 체크 후 저장

### 실행

- git으로 push 하면 자동으로 build now 실행

## 배포 스크립트 작성

- 무중단 배포를 간단하게 하기 위해 shell로 스크립트 작성
- deploy.sh

```sh
#!/user/bin/env bash

function create_docker_image_blue(){

  echo "> blue docker image 만들기"

  ./gradlew clean build

  docker build -t app:0.1 .

}

function create_docker_image_green(){

  echo "> green docker image 만들기"

  ./gradlew clean build

  docker build -t app:0.2 .
}

function execute_blue(){
    docker ps -q --filter "name=app_blue" || grep -q . && docker stop app_blue && docker rm app_blue || true

    sleep 10

    docker-compose -p app-blue -f docker-compose.blue.yml up -d

    sleep 10

    echo "GREEN:8082 종료"
    docker-compose -p app-green -f docker-compose.green.yml down

    #dangling=true : 불필요한 이미지 지우기
    docker rmi -f $(docker images -f "dangling=true" -q) || true
}

function execute_green(){
  docker ps -q --filter "name=app_green" || grep -q . && docker stop app_green && docker rm app_green || true

    echo "GREEN:8082 실행"
    docker-compose -p app-green -f docker-compose.green.yml up -d

    sleep 10

    echo "BLUE:8081 종료"
    docker-compose -p app-blue -f docker-compose.blue.yml down

    #dangling=true : 불필요한 이미지 지우기
    docker rmi -f $(docker images -f "dangling=true" -q) || true
}

# 현재 사용중인 어플리케이션 확인
# 8082포트의 값이 없으면 8081포트 사용 중
# shellcheck disable=SC2046
RUNNING_GREEN=$(lsof -ti tcp:8082)
RUNNING_BLUE=$(lsof -ti tcp:8081)

# Blue or Green
if [ -z ${RUNNING_GREEN} ]
  then
    # 초기 실행 : BLUE도 실행중이지 않을 경우
    if [ -z ${RUNNING_BLUE} ]
    then
      echo "구동 앱 없음 => BLUE 실행"

      create_docker_image_blue

      sleep 10

      docker-compose -p app-blue -f docker-compose.blue.yml up -d

    else
      # 8082포트로 어플리케이션 구동
      echo "BLUE:8081 실행 중"

      create_docker_image_green

      execute_green

    fi
else
    # 8081포트로 어플리케이션 구동
    echo "GREEN:8082 실행 중"

    echo "BLUE:8081 실행"

    create_docker_image_blue

    execute_blue

fi


# 새로운 어플리케이션 구동 후 현재 어플리케이션 종료
#kill -15 ${RUNNING_PORT_PID}
```

## 테스트 및 실행

- 터미널에서 sh deploy.sh를 실행하면 blue버전이 실행된다.
- 연속해서 sh deploy.sh를 실행하면 blue 버전과 green 버전이 번갈아가면서 실행된다.
- jenkins에서 execute shell에 sh deploy.sh를 입력해놓기만 하면 push 명령 실행 시 자동으로 무중단 배포를 실행할 수 있다.