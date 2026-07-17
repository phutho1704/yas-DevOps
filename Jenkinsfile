def normalizeBranchName(String branchName) {
    if (!branchName) {
        return 'main'
    }

    return branchName
        .replaceFirst(/^refs\/heads\//, '')
        .replaceFirst(/^origin\//, '')
        .trim()
}

// Returns true if any changed file path starts with the given module prefix.
// Relies on env.CHANGED_FILES computed in the Checkout stage via `git diff`
// instead of Jenkins' built-in changeset/changelog (which can be empty when
// using a custom `checkout([$class: 'GitSCM', ...])` step).
def moduleChanged(String moduleName) {
    def changed = (env.CHANGED_FILES ?: '').split('\n')
    return changed.any { it.trim().startsWith("${moduleName}/") }
}

def anyModuleChanged(List<String> modules) {
    return modules.any { moduleChanged(it) }
}

pipeline {
    agent any

    tools {
        jdk 'JDK21'
        maven 'Maven3.9'
    }

    environment {
        SONARQUBE_ENV = 'SonarQubeServer'
        TESTCONTAINERS_RYUK_DISABLED = 'true'
        ALL_MODULES = 'product,media,cart,order,inventory,payment,tax,rating,location'
    }

    stages {

        // ========================
        // CHECKOUT
        // ========================
        stage('Checkout') {
            steps {
                script {
                    def rawBranchName = env.CHANGE_BRANCH ?: env.BRANCH_NAME ?: env.GIT_BRANCH ?: 'main'
                    def branchName = normalizeBranchName(rawBranchName)

                    env.BRANCH_NAME_SAFE = branchName
                    echo "Checking out branch: ${branchName}"

                    checkout([
                        $class: 'GitSCM',
                        branches: [[name: "*/${branchName}"]],
                        userRemoteConfigs: scm.userRemoteConfigs,
                        extensions: [[$class: 'CloneOption', depth: 0]]
                    ])

                    // --- Compute changed files ourselves (do NOT rely on changeset/changelog) ---
                    // Prefer diffing against the previous successful build's commit on this branch;
                    // fall back to HEAD~1 for the very first build, or to "everything changed"
                    // if neither works (e.g. shallow history / first commit).
                    sh 'git fetch --tags --force || true'

                    def previousCommit = env.GIT_PREVIOUS_SUCCESSFUL_COMMIT
                    def diffTarget = previousCommit ? previousCommit : 'HEAD~1'

                    def changedFiles = sh(
                        script: """
                            if git rev-parse --verify ${diffTarget} >/dev/null 2>&1; then
                                git diff --name-only ${diffTarget} HEAD
                            else
                                echo "__FULL_BUILD__"
                            fi
                        """,
                        returnStdout: true
                    ).trim()

                    if (changedFiles == '__FULL_BUILD__' || changedFiles == '') {
                        echo "No previous commit reference found; treating all modules as changed."
                        env.CHANGED_FILES = env.ALL_MODULES.split(',').collect { "${it}/CHANGED" }.join('\n')
                    } else {
                        env.CHANGED_FILES = changedFiles
                    }

                    echo "Changed files:\n${env.CHANGED_FILES}"
                }
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
                    when { expression { moduleChanged('product') } }
                    steps { processModule("product") }
                }

                stage('Media') {
                    when { expression { moduleChanged('media') } }
                    steps { processModule("media") }
                }

                stage('Cart') {
                    when { expression { moduleChanged('cart') } }
                    steps { processModule("cart") }
                }

                stage('Order') {
                    when { expression { moduleChanged('order') } }
                    steps { processModule("order") }
                }

                stage('Inventory') {
                    when { expression { moduleChanged('inventory') } }
                    steps { processModule("inventory") }
                }

                stage('Payment') {
                    when { expression { moduleChanged('payment') } }
                    steps { processModule("payment") }
                }

                stage('Tax') {
                    when { expression { moduleChanged('tax') } }
                    steps { processModule("tax") }
                }

                stage('Rating') {
                    when { expression { moduleChanged('rating') } }
                    steps { processModule("rating") }
                }

                stage('Location') {
                    when { expression { moduleChanged('location') } }
                    steps { processModule("location") }
                }
            }
        }

        // ========================
        // FALLBACK
        // ========================
        stage('No Changes Fallback') {
            when {
                expression { !anyModuleChanged(env.ALL_MODULES.split(',') as List) }
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
                expression {
                    def changed = anyModuleChanged(env.ALL_MODULES.split(',') as List)
                    def sonarEnabled = !((env.SKIP_SONAR ?: 'false').toBoolean()) &&
                        ((env.SONAR_HOST_URL ?: '').trim()) &&
                        ((env.SONAR_TOKEN ?: '').trim())
                    return changed && sonarEnabled
                }
            }
            steps {
                sh """
                echo "Running SonarQube analysis against ${env.SONAR_HOST_URL}"
                mvn compile -DskipTests

                mvn sonar:sonar \
                -Dsonar.projectKey=yas-project \
                -Dsonar.branch.name="${env.BRANCH_NAME_SAFE}" \
                -Dsonar.coverage.jacoco.xmlReportPaths=**/target/site/jacoco/jacoco.xml \
                -Dsonar.host.url="${env.SONAR_HOST_URL}" \
                -Dsonar.token="${env.SONAR_TOKEN}" \
                -DskipTests
                """
            }
        }

        stage('SonarQube Analysis Skipped') {
            when {
                expression {
                    def changed = anyModuleChanged(env.ALL_MODULES.split(',') as List)
                    def sonarSkipped = ((env.SKIP_SONAR ?: 'false').toBoolean()) ||
                        !((env.SONAR_HOST_URL ?: '').trim()) ||
                        !((env.SONAR_TOKEN ?: '').trim())
                    return changed && sonarSkipped
                }
            }
            steps {
                echo 'SonarQube skipped because SONAR_HOST_URL/SONAR_TOKEN are not configured.'
            }
        }

        // ========================
        // QUALITY GATE
        // ========================
        stage('Quality Gate') {
            when {
                expression {
                    def changed = anyModuleChanged(env.ALL_MODULES.split(',') as List)
                    def sonarEnabled = !((env.SKIP_SONAR ?: 'false').toBoolean()) &&
                        ((env.SONAR_HOST_URL ?: '').trim()) &&
                        ((env.SONAR_TOKEN ?: '').trim())
                    return changed && sonarEnabled
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

            mvn clean test jacoco:report \
            -pl ${moduleName} -am \
            -DskipITs=true \
            -DskipTests=false \
            -DtrimStackTrace=true
            """

            def coverageReport = sh(
                script: "find . -path '*/target/site/jacoco/jacoco.xml' | head -n 1",
                returnStdout: true
            ).trim()

            if (coverageReport) {
                echo "Found JaCoCo report: ${coverageReport}"
            } else {
                echo "No JaCoCo report found; coverage will not be published"
            }

            // Publish test results
            junit allowEmptyResults: true,
                  testResults: "**/target/surefire-reports/*.xml, **/target/failsafe-reports/*.xml"

            if (coverageReport) {
                recordCoverage(
                    tools: [[parser: 'JACOCO', pattern: coverageReport]],
                    qualityGates: [
                        [threshold: 70.0, metric: 'LINE', baseline: 'PROJECT', criticality: 'FAILURE']
                    ]
                )
            }
        }
    }
}