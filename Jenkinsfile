pipeline {
    agent none

    environment {
        // ── JFrog (archive only) ───────────────────────
        JFROG_URL      = 'http://20.219.37.20:8082/artifactory'
        JFROG_REPO     = 'amazon-generic-local'

        // ── ACR (AKS pulls from here) ──────────────────
        ACR_REGISTRY   = 'ChiduACR.azurecr.io'          // ADDED

        // ── Image config ───────────────────────────────
        IMAGE_NAME     = 'amazon-app'
        IMAGE_TAG      = "${env.BUILD_NUMBER}"
        TAR_FILE       = "${IMAGE_NAME}-${IMAGE_TAG}.tar"
        FULL_IMAGE     = "ChiduACR.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"  // CHANGED: was JFrog Docker path
        K8S_NAMESPACE  = 'amazon'
    }

    stages {

        // ──────────────────────────────────────────────
        // STAGE 1: Build Docker image on macOS Docker slave
        // ──────────────────────────────────────────────

        // stage('Build Docker Image') {
        //     agent { label 'azure-vm-agent' }

        //     steps {
        //         checkout scm

        //         sh '''
        //         echo "=== Enabling buildx ==="
        //         docker buildx create --use || true
        
        //         echo "=== Building amd64 image ==="
        //         docker buildx build \
        //           --platform linux/amd64 \
        //           -t ${IMAGE_NAME}:${IMAGE_TAG} \
        //           -f Dockerfile . \
        //           --push
        //         '''
        //     }
        // }
        stage('Build Docker Image') {
            agent { label 'azure-vm-agent' }
            steps {
                checkout scm
                script {
                    docker.build("${IMAGE_NAME}:${IMAGE_TAG}", "--no-cache -f Dockerfile .")
                    // docker.build("${IMAGE_NAME}:${IMAGE_TAG}","--platform=linux/amd64 -f Dockerfile .")
                }
            }
        }

        // ──────────────────────────────────────────────
        // STAGE 2: Save tar → JFrog Generic (archive)
        //          Push image → ACR (AKS pulls from here)
        // ──────────────────────────────────────────────
        stage('Push Artifact & Image') {                 // RENAMED for clarity
            agent { label 'azure-vm-agent' }
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'jfrog-creds',
                        usernameVariable: 'JFROG_USER',
                        passwordVariable: 'JFROG_PASS'
                    ),
                    usernamePassword(                     // ADDED: ACR credential block
                        credentialsId: 'acr-creds',
                        usernameVariable: 'ACR_USER',
                        passwordVariable: 'ACR_PASS'
                    )
                ]) {
                    sh """
                        # ── 1. Save image as tar ──────────────────────────────
                        echo "=== Saving image as tar ==="
                        docker save ${IMAGE_NAME}:${IMAGE_TAG} -o ${TAR_FILE}
                        ls -lh ${TAR_FILE}

                        # ── 2. Upload tar to JFrog Generic (audit archive) ────
                        echo "=== Uploading tar to JFrog Generic repo ==="
                        curl -u ${JFROG_USER}:${JFROG_PASS} \
                            -X PUT \
                            "${JFROG_URL}/${JFROG_REPO}/${IMAGE_NAME}/${TAR_FILE}" \
                            -T ${TAR_FILE} \
                            --progress-bar \
                            -w "\\nHTTP Status: %{http_code}\\n"

                        echo "=== Verifying tar in JFrog ==="
                        curl -s -u ${JFROG_USER}:${JFROG_PASS} \
                            "${JFROG_URL}/api/storage/${JFROG_REPO}/${IMAGE_NAME}/${TAR_FILE}" \
                            | python3 -m json.tool

                        # ── 3. Push image to ACR (what AKS actually pulls) ────
                        echo "=== Logging in to ACR ==="
                        docker login ${ACR_REGISTRY} \
                            -u ${ACR_USER} \
                            -p ${ACR_PASS}

                        echo "=== Tagging image for ACR ==="
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${FULL_IMAGE}

                        echo "=== Pushing image to ACR ==="
                        docker push ${FULL_IMAGE}

                        echo "=== Verifying image in ACR ==="
                        curl -s -u ${ACR_USER}:${ACR_PASS} \
                            https://${ACR_REGISTRY}/v2/${IMAGE_NAME}/tags/list

                        # ── 4. Cleanup ────────────────────────────────────────
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

        // ──────────────────────────────────────────────
        // STAGE 3: Deploy to AKS via Kubernetes plugin pod
        // ──────────────────────────────────────────────

        stage('Deploy to AKS') {
            agent { label 'azure-vm-agent' }

            steps {
                withCredentials([file(credentialsId: 'kubeconfig-aks', variable: 'KUBECONFIG')]) {
                    sh """
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
                        kubectl rollout status deployment/amazon-deployment \
                            -n ${K8S_NAMESPACE} --timeout=180s
                    """
        }
    }
}

        // ──────────────────────────────────────────────
        // STAGE 4: Confirm deployment
        // k8s plugin pod auto-destroys after Stage 3 ends
        // ──────────────────────────────────────────────
        stage('Confirm & Cleanup') {
            agent { label 'azure-vm-agent' }
            steps {
                withCredentials([file(credentialsId: 'kubeconfig-aks', variable: 'KUBECONFIG')]) {
                    sh """
                        echo "=== Deployed pods ==="
                        kubectl get pods -n ${K8S_NAMESPACE}
                        echo "=== Services ==="
                        kubectl get svc  -n ${K8S_NAMESPACE}
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
                to: 'build.chidambar@gmail.com',
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
                to: 'build.chidambar@gmail.com',
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
                to: 'build.chidambar@gmail.com',
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