# Module 5 – Application Development

**Region:** `ap-south-1` (Mumbai) | **Application:** `ecommerce-app` | **Runtime:** Java 17 / Spring Boot `3.4.3`

This module scaffolds a Java 17 Spring Boot microservice (`ecommerce-app`) with REST and Spring Boot Actuator health/info endpoints, and runs Maven verification (`mvn clean verify`) to compile, test, and package the executable JAR before containerization.

## Architecture & Key Parameters

| Parameter | Value | Notes | 
| ----- | ----- | ----- | 
| **Application Directory** | `~/aws-eks-project/application/ecommerce-app` | Maven project root | 
| **Java / Spring Boot** | Java `17` / Spring Boot `3.4.3` | Web + Actuator starters | 
| **Artifact** | `com.example:ecommerce-app:1.0.0` | Packaged as `target/ecommerce-app-1.0.0.jar` | 
| **Server Port** | `8080` | Matches Kubernetes/ALB target port | 
| **Health Endpoint** | `/actuator/health` | Used by ALB health checks and Kubernetes probes | 

## Step 1 – Initialize Application Directory & Maven `pom.xml`

Create the source directory structure (if not already present) and generate `pom.xml` with Spring Boot Web, Actuator, and Test dependencies:

```
APP_DIR=~/aws-eks-project/application/ecommerce-app
mkdir -p "$APP_DIR/src/main/java/com/example/ecommerce" "$APP_DIR/src/main/resources"

cat << 'EOF' > "$APP_DIR/pom.xml"
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.4.3</version>
        <relativePath/>
    </parent>
    <groupId>com.example</groupId>
    <artifactId>ecommerce-app</artifactId>
    <version>1.0.0</version>
    <name>ecommerce-app</name>
    <properties>
        <java.version>17</java.version>
    </properties>
    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>
    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>
</project>
EOF
```

* **Verification:** `ls -lh "$APP_DIR/pom.xml"` confirms `pom.xml` exists in `~/aws-eks-project/application/ecommerce-app`.

## Step 2 – Create Spring Boot Application Entrypoint & REST Controller

Create `EcommerceApplication.java` and `HealthController.java` to expose the root `/` status endpoint:

```
cat << 'EOF' > "$APP_DIR/src/main/java/com/example/ecommerce/EcommerceApplication.java"
package com.example.ecommerce;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class EcommerceApplication {
    public static void main(String[] args) {
        SpringApplication.run(EcommerceApplication.class, args);
    }
}
EOF

cat << 'EOF' > "$APP_DIR/src/main/java/com/example/ecommerce/HealthController.java"
package com.example.ecommerce;

import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthController {
    @GetMapping("/")
    public Map<String, String> home() {
        return Map.of("service", "ecommerce-app", "status", "running");
    }
}
EOF
```

* **Verification:** Both `.java` files exist under `src/main/java/com/example/ecommerce/`.

## Step 3 – Configure `application.properties`

Configure the HTTP port (`8080`) and Spring Boot Actuator endpoints:

```
cat << 'EOF' > "$APP_DIR/src/main/resources/application.properties"
server.port=8080
management.endpoints.web.exposure.include=health,info,prometheus
management.endpoint.health.show-details=never
EOF
```

> **Note:** On Spring Boot `3.4+`, `/actuator/health` and `/actuator/info` work out of the box with `spring-boot-starter-actuator`. If you later scrape `/actuator/prometheus` directly from the app, add `io.micrometer:micrometer-registry-prometheus` to `pom.xml`.

* **Verification:** `cat "$APP_DIR/src/main/resources/application.properties"` shows `server.port=8080` and the Actuator properties.

## Step 4 – Build, Test, and Package with Maven

Run `mvn clean verify` inside `$APP_DIR` to validate dependencies, run tests, and produce the executable Spring Boot JAR:

```
cd "$APP_DIR"
mvn clean verify
ls -lh target/*.jar
```

* **Verification:** Maven finishes with `BUILD SUCCESS`, and `target/ecommerce-app-1.0.0.jar` is created and ready for Docker packaging in Module 6.
