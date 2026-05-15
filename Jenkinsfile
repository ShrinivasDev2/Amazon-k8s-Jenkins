pipeline {
    agent none

    environment {
        JFROG_URL      = 'http://52.150.22.255:8081/artifactory'
        JFROG_REPO     = 'amazon'

        ACR_NAME       = 'shrinivasamazonaks'
        ACR_REGISTRY   = 'shrinivasamazonaks.azurecr.io'

        IMAGE_NAME     = 'amazon-app'
        IMAGE_TAG      = "${env.BUILD_NUMBER}"
        TAR_FILE       = "${IMAGE_NAME}-${IMAGE_TAG}.tar"
        FULL_IMAGE     = "${ACR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

        AKS_RG         = 'Shrinivas-RG'
        AKS_NAME       = 'shrinivas-aks'
        K8S_NAMESPACE  = 'amazon'
    }

    stages {

        stage('Build Docker Image') {
            agent { label 'azure-ubuntu-VM' }
            steps {
                checkout scm
                script {
                    docker.build("${IMAGE_NAME}:${IMAGE_TAG}", "--no-cache -f Dockerfile .")
                }
            }
        }

        stage('Push Artifact & Image') {
            agent { label 'azure-vm-agent' }
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'JFrog',
                        usernameVariable: 'JFROG_USER',
                        passwordVariable: 'JFROG_PASS'
                    ),
                    azureServicePrincipal('azure-sp')
                ]) {
                    sh """
                        set -e

                        echo "=== Azure Login ==="
                        az login --service-principal \\
                            -u "$AZURE_CLIENT_ID" \\
                            -p "$AZURE_CLIENT_SECRET" \\
                            -t "$AZURE_TENANT_ID"

                        az account set --subscription "$AZURE_SUBSCRIPTION_ID"

                        echo "=== Saving image as tar ==="
                        docker save ${IMAGE_NAME}:${IMAGE_TAG} -o ${TAR_FILE}
                        ls -lh ${TAR_FILE}

                        echo "=== Uploading tar to JFrog Generic repo ==="
                        curl -u ${JFROG_USER}:${JFROG_PASS} \\
                            -X PUT \\
                            "${JFROG_URL}/${JFROG_REPO}/${IMAGE_NAME}/${TAR_FILE}" \\
                            -T ${TAR_FILE} \\
                            --progress-bar \\
                            -w "\\nHTTP Status: %{http_code}\\n"

                        echo "=== Verifying tar in JFrog ==="
                        curl -s -u ${JFROG_USER}:${JFROG_PASS} \\
                            "${JFROG_URL}/api/storage/${JFROG_REPO}/${IMAGE_NAME}/${TAR_FILE}" \\
                            | python3 -m json.tool

                        echo "=== Logging in to ACR using Azure SP ==="
                        az acr login --name ${ACR_NAME}

                        echo "=== Tagging image for ACR ==="
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${FULL_IMAGE}

                        echo "=== Pushing image to ACR ==="
                        docker push ${FULL_IMAGE}

                        echo "=== Cleaning up local files ==="
                        rm -f ${TAR_FILE}
                        docker rmi ${IMAGE_NAME}:${IMAGE_TAG} ${FULL_IMAGE} || true

                        echo "=== Summary ==="
                        echo "JFrog archive : ${JFROG_URL}/${JFROG_REPO}/${IMAGE_NAME}/${TAR_FILE}"
                        echo "ACR image     : ${FULL_IMAGE}"
                    """
                }
            }
        }

        stage('Deploy to AKS') {
            agent { label 'azure-vm-agent' }
            steps {
                withCredentials([
                    azureServicePrincipal('azure-sp'),
                    file(credentialsId: 'aks-config', variable: 'KUBECONFIG')
                ]) {
                    sh """
                        set -e

                        echo "=== Azure Login ==="
                        az login --service-principal \\
                            -u "$AZURE_CLIENT_ID" \\
                            -p "$AZURE_CLIENT_SECRET" \\
                            -t "$AZURE_TENANT_ID"

                        az account set --subscription "$AZURE_SUBSCRIPTION_ID"

                        echo "=== Using kubeconfig from Jenkins credential ==="
                        kubectl config current-context || true

                        echo "=== Substituting image placeholder ==="
                        sed -i "s|DOCKER_IMAGE_PLACEHOLDER|${FULL_IMAGE}|g" k8s/deployment.yaml

                        echo "=== Verifying substitution ==="
                        grep 'image:' k8s/deployment.yaml

                        echo "=== Applying manifests ==="
                        kubectl apply -f k8s/namespace.yaml
                        kubectl apply -f k8s/configmap.yaml  -n ${K8S_NAMESPACE}
                        kubectl apply -f k8s/deployment.yaml -n ${K8S_NAMESPACE}
                        kubectl apply -f k8s/service.yaml    -n ${K8S_NAMESPACE}
                        kubectl apply -f k8s/ingress.yaml    -n ${K8S_NAMESPACE}
                        kubectl apply -f k8s/hpa.yaml        -n ${K8S_NAMESPACE}

                        echo "=== Waiting for rollout ==="
                        kubectl rollout status deployment/amazon-deployment \\
                            -n ${K8S_NAMESPACE} --timeout=180s
                    """
                }
            }
        }

        stage('Confirm Deployment') {
            agent { label 'azure-vm-agent' }
            steps {
                withCredentials([file(credentialsId: 'aks-config', variable: 'KUBECONFIG')]) {
                    sh """
                        set -e
                        echo "=== Deployed pods ==="
                        kubectl get pods -n ${K8S_NAMESPACE}
                        echo "=== Services ==="
                        kubectl get svc -n ${K8S_NAMESPACE}
                        echo "=== Ingress ==="
                        kubectl get ingress -n ${K8S_NAMESPACE}
                        echo "=== HPA ==="
                        kubectl get hpa -n ${K8S_NAMESPACE}
                    """
                }
            }
        }
    }

    post {
        success {
            mail(
                to: 'shrinivas.devops.reports@gmail.com',
                subject: "✅ [SUCCESS] Amazon App - Build #${env.BUILD_NUMBER}",
                body: """\
Build Status:  SUCCESS
Job:           ${env.JOB_NAME}
Build Number:  #${env.BUILD_NUMBER}
Branch:        ${env.GIT_BRANCH}
ACR Image:     ${env.FULL_IMAGE}
JFrog Tar:     ${env.JFROG_URL}/${env.JFROG_REPO}/${env.IMAGE_NAME}/${env.IMAGE_NAME}-${env.IMAGE_TAG}.tar
Duration:      ${currentBuild.durationString}

View build:    ${env.BUILD_URL}
"""
            )
        }

        failure {
            mail(
                to: 'shrinivas.devops.reports@gmail.com',
                subject: "❌ [FAILED] Amazon App - Build #${env.BUILD_NUMBER}",
                body: """\
Build Status:  FAILED
Job:           ${env.JOB_NAME}
Build Number:  #${env.BUILD_NUMBER}
Branch:        ${env.GIT_BRANCH}
Failed Stage:  ${env.STAGE_NAME}

View logs:     ${env.BUILD_URL}console
"""
            )
        }

        always {
            mail(
                to: 'shrinivas.devops.reports@gmail.com',
                subject: "[CI] Amazon App Build #${env.BUILD_NUMBER} - ${currentBuild.currentResult}",
                body: """\
Build #${env.BUILD_NUMBER} finished — ${currentBuild.currentResult}

Job:      ${env.JOB_NAME}
Branch:   ${env.GIT_BRANCH}
Duration: ${currentBuild.durationString}

${env.BUILD_URL}
"""
            )
        }
    }
}
