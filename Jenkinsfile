pipeline {
    agent any

    environment {
        IMAGE_NAME = 'sentiment-ai'
        REGISTRY = 'ghcr.io/3ollnai'
        IMAGE_TAG = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
    }

  stages {
        stage('Checkout') {
            steps {
                checkout scm
                echo "Branche : ${env.BRANCH_NAME}"
                echo "Commit : ${env.GIT_COMMIT}"
                sh 'git log --oneline -5'
            }
        }

        stage('Lint') {
            steps {
                sh '''
                    docker run --rm \
                    --volumes-from jenkins \
                    -w $WORKSPACE \
                    python:3.12-slim \
                    sh -c "pip install flake8 -q && flake8 src/ --max-line-length=100"
                '''
            }
        }

        stage('IaC Validate') {
            steps {
                dir('infra') {
                    sh 'terraform init -backend=false -input=false'
                    sh 'terraform fmt -check'
                    sh 'terraform validate'
                }
            }
        }

        stage('Build & Test') {
            steps {
                sh '''
                    docker build --no-cache -t ${IMAGE_NAME}:${IMAGE_TAG} .

                    docker rm -f test-runner 2>/dev/null || true

                    set +e
                    docker run \
                    -e CI=true \
                    --name test-runner \
                    ${IMAGE_NAME}:${IMAGE_TAG} \
                    pytest tests/ -v \
                    --cov=src \
                    --cov-report=xml:/tmp/coverage.xml \
                    --cov-report=term-missing \
                    --cov-fail-under=70
                    TEST_EXIT_CODE=$?
                    set -e

                    docker cp test-runner:/tmp/coverage.xml ./coverage.xml 2>/dev/null || true
                    docker rm -f test-runner 2>/dev/null || true

                    sed -i 's#/app/#./#g' coverage.xml 2>/dev/null || true
                    sed -i 's#filename="src/#filename="src/#g' coverage.xml 2>/dev/null || true

                    exit $TEST_EXIT_CODE
                '''
            }
            post {
                failure {
                    echo 'Tests échoués ou coverage insuffisant (< 70%)'
                }
            }
        }

        stage('SonarQube Analysis') {
            environment {
                SONARQUBE_TOKEN = credentials('sonar-token')
            }
            steps {
                withSonarQubeEnv('sonarqube') {
                    sh '''
                        docker run --rm \
                        --network cicd-network \
                        --volumes-from jenkins \
                        -w "$WORKSPACE" \
                        -e SONAR_HOST_URL="$SONAR_HOST_URL" \
                        -e SONAR_TOKEN="$SONARQUBE_TOKEN" \
                        sonarsource/sonar-scanner-cli:latest \
                        sonar-scanner \
                        -Dsonar.projectKey=sentiment-ai \
                        -Dsonar.projectName=SentimentAI \
                        -Dsonar.projectBaseDir="$WORKSPACE" \
                        -Dsonar.sources=src \
                        -Dsonar.python.version=3.11 \
                        -Dsonar.python.coverage.reportPaths=coverage.xml \
                        -Dsonar.sourceEncoding=UTF-8 \
                        -Dsonar.scanner.metadataFilePath=$WORKSPACE/report-task.txt
                    '''
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 15, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Security Scan') {
            steps {
                sh '''
                    docker run --rm \
                    -v /var/run/docker.sock:/var/run/docker.sock \
                    -v trivy-cache:/root/.cache/trivy \
                    aquasec/trivy:latest image \
                    --severity HIGH,CRITICAL \
                    --exit-code 0 \
                    --format table \
                    ${IMAGE_NAME}:${IMAGE_TAG}
                '''
            }
            post {
                failure {
                    echo 'Vulnérabilités CRITICAL ou HIGH détectées !'
                    echo 'Corrigez les dépendances avant de déployer.'
                }
            }
        }

        stage('Push') {
            when {
                expression {
                    return env.GIT_BRANCH == 'origin/main' || env.GIT_BRANCH == 'main'
                }
            }
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'github-token',
                    usernameVariable: 'REGISTRY_USER',
                    passwordVariable: 'REGISTRY_PASS'
                )]) {
                    sh """
                        echo \$REGISTRY_PASS | docker login ghcr.io \
                        -u \$REGISTRY_USER --password-stdin
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY}/${IMAGE_NAME}:latest
                        docker push ${REGISTRY}/${IMAGE_NAME}:latest
                    """
                }
            }
        }

        stage('IaC Apply') {
            when {
                expression {
                    return env.GIT_BRANCH == 'origin/main' || env.GIT_BRANCH == 'main'
                }
            }
            steps {
                dir('infra') {
                    sh 'terraform init -input=false'
                    sh '''
                        NETWORK_ID=$(docker network inspect cicd-network --format "{{.Id}}" 2>/dev/null || echo "")
                        if [ -n "$NETWORK_ID" ]; then
                            terraform import docker_network.cicd $NETWORK_ID 2>/dev/null || true
                        fi
                        CONTAINER_ID=$(docker inspect sentiment-staging --format "{{.Id}}" 2>/dev/null || echo "")
                        if [ -n "$CONTAINER_ID" ]; then
                            terraform import docker_container.sentiment_staging $CONTAINER_ID 2>/dev/null || true
                        fi
                        PROMETHEUS_ID=$(docker inspect prometheus --format "{{.Id}}" 2>/dev/null || echo "")
                        if [ -n "$PROMETHEUS_ID" ]; then
                            terraform import docker_container.prometheus $PROMETHEUS_ID 2>/dev/null || true
                        fi
                        GRAFANA_ID=$(docker inspect grafana --format "{{.Id}}" 2>/dev/null || echo "")
                        if [ -n "$GRAFANA_ID" ]; then
                            terraform import docker_container.grafana $GRAFANA_ID 2>/dev/null || true
                        fi
                    '''
                    sh """
                        terraform apply -auto-approve \
                        -var='image_tag=${IMAGE_TAG}'
                    """
                }
            }
        }

        stage('Deploy Staging') {
            when {
                expression {
                    return env.GIT_BRANCH == 'origin/main' || env.GIT_BRANCH == 'main'
                }
            }
            steps {
                sh '''
                    sleep 5
                    docker run --rm \
                    --network cicd-network \
                    curlimages/curl:latest \
                    curl -f http://sentiment-staging:8000/health || exit 1
                '''
            }
        }

stage('Smoke Test') {
    when {
        expression {
            return env.GIT_BRANCH == 'origin/main' || env.GIT_BRANCH == 'main'
        }
    }
    steps {
        sh '''
            echo "Attente demarrage (10s)..."
            sleep 10

            docker run --rm --network cicd-network curlimages/curl:latest \
                curl -f http://sentiment-staging:8000/health || exit 1
            echo "/health OK"

            docker run --rm --network cicd-network curlimages/curl:latest \
                curl -s http://sentiment-staging:8000/metrics | \
                grep -q sentiment_predictions_total || exit 1
            echo "/metrics OK"

            echo "Attente Prometheus scrape..."

            for i in $(seq 1 12); do
                docker run --rm --network cicd-network curlimages/curl:latest \
                    curl -s "http://prometheus:9090/api/v1/query?query=up%7Bjob%3D%22sentiment-ai%22%7D" | \
                    grep -q '"value"' && break

                echo "Prometheus pas encore prêt, tentative $i/12..."
                sleep 5
            done

            docker run --rm --network cicd-network curlimages/curl:latest \
                curl -s "http://prometheus:9090/api/v1/query?query=up%7Bjob%3D%22sentiment-ai%22%7D" | \
                grep -q '"value"' || exit 1

            echo "Prometheus scrape sentiment-ai : UP"

            docker run --rm --network cicd-network curlimages/curl:latest \
                curl -f http://grafana:3000/api/health || exit 1
            echo "Grafana OK"
        '''
    }
    post {
        failure {
            sh 'docker logs prometheus || true'
            sh 'docker logs sentiment-staging || true'
            echo 'Smoke Test KO -- voir logs ci-dessus'
        }
    }
}
    post {
        always {
            sh 'docker compose down -v 2>/dev/null || true'
        }
        success {
            echo "Pipeline réussi ! Image : ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        }
        failure {
            echo 'Pipeline échoué. Consultez les logs ci-dessus.'
        }
    }
}
