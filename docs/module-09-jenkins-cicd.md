# Module 9 – Jenkins CI/CD Pipeline

**Region:** `ap-south-1` (Mumbai) | **Cluster:** `ecommerce-eks` | **Namespace:** `production` | **Pipeline File:** `jenkins/Jenkinsfile`

This module defines a declarative Jenkins CI/CD pipeline (`~/aws-eks-project/jenkins/Jenkinsfile`) that checks out source code from Git, compiles and tests the Java 17 Maven application, runs SonarQube static code analysis and Trivy container vulnerability scanning, pushes the tagged Docker image to Amazon ECR, and performs an atomic Helm rollout to Amazon EKS.

## Architecture & Pipeline Stages

| Stage | Tooling | Purpose | 
| ----- | ----- | ----- | 
| **1. Checkout** | Git SCM | Clones the repository branch triggering the pipeline | 
| **2. Maven Build & Test** | Maven (`mvn clean verify`) | Compiles Java 17 code, runs unit tests, and packages the JAR | 
| **3. SonarQube Analysis** | SonarQube (`mvn sonar:sonar`) | Performs static code quality and security analysis | 
| **4. Docker Build & Trivy Scan** | Docker + Trivy | Builds image tagged `${BUILD_NUMBER}` and fails on `CRITICAL` CVEs | 
| **5. Push to Amazon ECR** | AWS CLI + Docker | Logs into ECR in `ap-south-1`, tags, and pushes the image | 
| **6. Deploy to EKS via Helm** | `aws eks` + `helm upgrade` | Updates `kubeconfig` and deploys `./helm/ecommerce` atomically | 
| **7. Verify Rollout** | `kubectl rollout status` | Confirms pods roll out cleanly in `production` | 

## Prerequisites for the Jenkins Agent

Before running this pipeline on a Jenkins controller or agent node, ensure the following are configured:

1. **CLI Tools Installed on Agent:** `git`, `java` (17), `mvn`, `docker` (with the `jenkins` user added to the `docker` group), `trivy`, `aws` (AWS CLI v2), `kubectl`, and `helm`.

2. **AWS Permissions:** The Jenkins EC2 instance profile (such as `ubuntu-eks-devops-role`) or configured AWS credentials must have permissions for Amazon ECR (`ecr:*`) and EKS (`eks:DescribeCluster`).

3. **Jenkins Credentials & Plugins:**

   * **Secret text credential:** ID `aws-account-id` containing your 12-digit AWS Account ID.

   * **SonarQube server configuration:** Configured in Jenkins Global Configuration under the name `SonarQube` (with the SonarQube Scanner plugin installed).

## Step 1 – Create `jenkins/Jenkinsfile`

Ensure the `~/aws-eks-project/jenkins` directory exists and write the declarative `Jenkinsfile`:

```
mkdir -p ~/aws-eks-project/jenkins

cat << 'EOF' > ~/aws-eks-project/jenkins/Jenkinsfile
pipeline {
    agent any

    environment {
        AWS_REGION     = 'ap-south-1'
        AWS_ACCOUNT_ID = credentials('aws-account-id')
        ECR_REPO       = 'ecommerce-app'
        CLUSTER_NAME   = 'ecommerce-eks'
        NAMESPACE      = 'production'
        IMAGE_TAG      = "${BUILD_NUMBER}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Maven Build & Test') {
            steps {
                dir('application/ecommerce-app') {
                    sh 'mvn clean verify'
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                dir('application/ecommerce-app') {
                    withSonarQubeEnv('SonarQube') {
                        sh 'mvn sonar:sonar'
                    }
                }
            }
        }

        stage('Docker Build & Trivy Scan') {
            steps {
                dir('application/ecommerce-app') {
                    sh '''
                      docker build -t $ECR_REPO:$IMAGE_TAG .
                      trivy image --exit-code 1 --severity CRITICAL $ECR_REPO:$IMAGE_TAG
                    '''
                }
            }
        }

        stage('Push to Amazon ECR') {
            steps {
                sh '''
                  aws ecr get-login-password --region $AWS_REGION | \
                    docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

                  docker tag $ECR_REPO:$IMAGE_TAG \
                    $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:$IMAGE_TAG

                  docker push \
                    $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:$IMAGE_TAG
                '''
            }
        }

        stage('Deploy to EKS via Helm') {
            steps {
                sh '''
                  aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

                  helm upgrade --install ecommerce-app ./helm/ecommerce \
                    --namespace $NAMESPACE \
                    --create-namespace \
                    --set image.repository=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO \
                    --set image.tag=$IMAGE_TAG \
                    --atomic \
                    --timeout 5m
                '''
            }
        }

        stage('Verify Rollout') {
            steps {
                sh '''
                  kubectl rollout status deployment/ecommerce-app -n $NAMESPACE --timeout=300s
                  kubectl get pods -n $NAMESPACE
                '''
            }
        }
    }
}
EOF
```

* **Verification:** `ls -lh ~/aws-eks-project/jenkins/Jenkinsfile` confirms the `Jenkinsfile` is saved and non-empty.

## Step 2 – Configure the Jenkins Pipeline Job

1. Open Jenkins in your browser and click **New Item**.

2. Enter a job name (e.g., `ecommerce-eks-pipeline`), select **Pipeline**, and click **OK**.

3. Under the **Pipeline** section:

   * Set **Definition** to **Pipeline script from SCM**.

   * Select **Git** as the SCM and enter your GitHub repository URL (`https://github.com/r-lakshman/aws-eks-devops-project.git`).

   * Set **Branch Specifier** to `*/main`.

   * Set **Script Path** to `jenkins/Jenkinsfile`.

4. Click **Save**, then click **Build Now** to trigger the pipeline.

* **Verification:** All seven stages (`Checkout` through `Verify Rollout`) complete in green, the new image tag (`${BUILD_NUMBER}`) appears in Amazon ECR, and `kubectl get pods -n production` shows updated pods running the new build tag.
