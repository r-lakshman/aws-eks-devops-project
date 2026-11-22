# Module 6 – Docker and Amazon ECR

**Region:** `ap-south-1` (Mumbai) | **ECR Repository:** `ecommerce-app` | **Image Tag:** `1.0.0`

This module packages the Java 17 Spring Boot microservice (`ecommerce-app`) into a slim, non-root container image using a multi-stage `Dockerfile`, authenticates Docker with Amazon ECR, and pushes the tagged image to AWS.

## Architecture & Key Parameters

| Parameter | Value | Notes | 
| ----- | ----- | ----- | 
| **Application Directory** | `~/aws-eks-project/application/ecommerce-app` | Build context containing `Dockerfile`, `pom.xml`, and `src/` | 
| **Builder Base Image** | `maven:3.9.9-eclipse-temurin-17` | Compiles and packages the Spring Boot JAR | 
| **Runtime Base Image** | `eclipse-temurin:17-jre-alpine` | Minimal Alpine JRE running as non-root `appuser` | 
| **ECR Repository** | `ecommerce-app` | Private repository in `ap-south-1` | 
| **Image Tag** | `1.0.0` | Versioned release artifact | 

## Step 1 – Create the Multi-Stage `Dockerfile`

Set the application directory variable and create a multi-stage `Dockerfile` that builds the JAR in a Maven stage and copies only the runtime artifact into a non-root Alpine JRE image:

```
APP_DIR=~/aws-eks-project/application/ecommerce-app

cat << 'EOF' > "$APP_DIR/Dockerfile"
FROM maven:3.9.9-eclipse-temurin-17 AS builder
WORKDIR /build
COPY pom.xml .
RUN mvn dependency:go-offline -q
COPY src ./src
RUN mvn clean package -DskipTests -q

FROM eclipse-temurin:17-jre-alpine
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY --from=builder /build/target/*.jar app.jar
USER appuser
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
EOF
```

* **Verification:** `cat "$APP_DIR/Dockerfile"` confirms the multi-stage `Dockerfile` is created with `USER appuser` and `EXPOSE 8080`.

## Step 2 – Authenticate Docker with Amazon ECR

Resolve your AWS Account ID, ensure the `ecommerce-app` ECR repository exists, and authenticate Docker to the `ap-south-1` ECR registry:

```
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO_URL="${ACCOUNT_ID}.dkr.ecr.ap-south-1.amazonaws.com/ecommerce-app"

aws ecr describe-repositories --repository-names ecommerce-app --region ap-south-1 >/dev/null 2>&1 || \
  aws ecr create-repository --repository-name ecommerce-app --region ap-south-1

aws ecr get-login-password --region ap-south-1 | \
  sudo docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.ap-south-1.amazonaws.com"
```

* **Verification:** Docker outputs `Login Succeeded`.

## Step 3 – Build and Push the Docker Image to ECR

Build the container image tagged with `${ECR_REPO_URL}:1.0.0` and push it to Amazon ECR:

```
sudo docker build -t "${ECR_REPO_URL}:1.0.0" "$APP_DIR"
sudo docker push "${ECR_REPO_URL}:1.0.0"
```

* **Verification:** Both `docker build` and `docker push` complete without errors and print the pushed image digest (`sha256:...`).

## Step 4 – Verify the Image in Amazon ECR

Confirm that tag `1.0.0` is stored in the `ecommerce-app` repository in `ap-south-1`:

```
aws ecr list-images --repository-name ecommerce-app --region ap-south-1
```

* **Verification:** The JSON output lists `"imageTag": "1.0.0"` under `imageIds`.
