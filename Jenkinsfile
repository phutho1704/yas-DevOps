pipeline {
    agent any

    tools {
        jdk 'JDK21'
        maven 'Maven3.9'
    }

    environment {
        SONARQUBE_ENV = 'SonarQubeServer'
        TESTCONTAINERS_RYUK_DISABLED = 'true'
    }

    stages {

        // ========================
        // CHECKOUT
        // ========================
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        // ========================
        // SECURITY SCAN
        // ========================
        stage('Security Scans') {
            parallel {
                stage('Gitleaks') {
                    steps {
                        sh "gitleaks detect --source . --report-format json --report-path gitleaks-report.json || true"
                    }
                }

                stage('Snyk') {
                    steps {
                        withCredentials([string(credentialsId: 'snyk-token', variable: 'SNYK_TOKEN')]) {
                            sh """
                            snyk auth \$SNYK_TOKEN
                            snyk test --all-projects --severity-threshold=high || true
                            """
                        }
                    }
                }
            }
        }

        // ========================
        // MODULE PROCESSING
        // ========================
        stage('Modules Processing') {
            parallel {

                stage('Product') {
                    when { changeset "product/**" }
                    steps { processModule("product") }
                }

                stage('Media') {
                    when { changeset "media/**" }
                    steps { processModule("media") }
                }

                stage('Cart') {
                    when { changeset "cart/**" }
                    steps { processModule("cart") }
                }

                stage('Customer') {
                    when { changeset "customer/**" }
                    steps { processModule("customer") }
                }

                stage('Order') {
                    when { changeset "order/**" }
                    steps { processModule("order") }
                }

                stage('Inventory') {
                    when { changeset "inventory/**" }
                    steps { processModule("inventory") }
                }

                stage('Payment') {
                    when { changeset "payment/**" }
                    steps { processModule("payment") }
                }

                stage('Tax') {
                    when { changeset "tax/**" }
                    steps { processModule("tax") }
                }

                stage('Rating') {
                    when { changeset "rating/**" }
                    steps { processModule("rating") }
                }

                stage('Location') {
                    when { changeset "location/**" }
                    steps { processModule("location") }
                }
            }
        }

        // ========================
        // FALLBACK
        // ========================
        stage('No Changes Fallback') {
            when {
                not {
                    anyOf {
                        changeset "product/**"
                        changeset "media/**"
                        changeset "cart/**"
                        changeset "customer/**"
                        changeset "order/**"
                        changeset "inventory/**"
                        changeset "payment/**"
                        changeset "tax/**"
                        changeset "rating/**"
                        changeset "location/**"
                    }
                }
            }
            steps {
                echo "No module changes detected → skipping build/test."
            }
        }

        // ========================
        // SONARQUBE
        // ========================
        stage('SonarQube Analysis') {
            when {
                anyOf {
                    changeset "product/**"
                    changeset "media/**"
                    changeset "cart/**"
                    changeset "customer/**"
                    changeset "order/**"
                    changeset "inventory/**"
                    changeset "payment/**"
                    changeset "tax/**"
                    changeset "rating/**"
                    changeset "location/**"
                }
            }
            steps {
                withSonarQubeEnv("${SONARQUBE_ENV}") {
                    sh """
                    mvn -B -DskipTests=false verify jacoco:report

                    mvn -B sonar:sonar \
                    -Dsonar.projectKey=yas-project \
                    -Dsonar.coverage.jacoco.xmlReportPaths=**/target/site/jacoco/jacoco.xml \
                    -DskipTests=false
                    """
                }
            }
        }

        // ========================
        // QUALITY GATE
        // ========================
        stage('Quality Gate') {
            when {
                anyOf {
                    changeset "product/**"
                    changeset "media/**"
                    changeset "cart/**"
                    changeset "customer/**"
                    changeset "order/**"
                    changeset "inventory/**"
                    changeset "payment/**"
                    changeset "tax/**"
                    changeset "rating/**"
                    changeset "location/**"
                }
            }
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }
    }

    post {
        success {
            echo 'Pipeline SUCCESS'
        }
        failure {
            echo 'Pipeline FAILED'
        }
    }
}

//
// ========================
// MODULE FUNCTION
// ========================
//
def processModule(String moduleName) {
    script {
        def javaHome = tool 'JDK21'
        def mvnHome = tool 'Maven3.9'

        withEnv([
            "JAVA_HOME=${javaHome}",
            "PATH+JAVA=${javaHome}/bin",
            "PATH+MAVEN=${mvnHome}/bin"
        ]) {

            sh """
            # Fix lỗi logback /tmp
            find . -name "logback.xml" -delete
            find . -name "logback-spring.xml" -delete

            mvn -B clean verify jacoco:report \
            -pl ${moduleName} -am \
            -DtrimStackTrace=true \
            -DskipTests=false
            """

            // Publish test results
            junit allowEmptyResults: true,
                  testResults: "**/target/surefire-reports/*.xml, **/target/failsafe-reports/*.xml"

            recordCoverage(
                tools: [[parser: 'JACOCO', pattern: '**/target/site/jacoco/jacoco.xml']],
                qualityGates: [
                    [threshold: 70.0, metric: 'LINE', baseline: 'PROJECT', criticality: 'FAILURE']
                ]
            )
        }
    }
}
