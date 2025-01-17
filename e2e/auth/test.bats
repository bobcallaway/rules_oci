bats_load_library "bats-support"
bats_load_library "bats-assert"

function setup_file() {
    cd $BATS_TEST_DIRNAME

    export PATH="$PATH:$BATS_TEST_DIRNAME/helpers/"
    export TAIL_PID="$(mktemp)"
    export AUTH_STDIN="$(mktemp -d)/stdin"

    mkfifo $AUTH_STDIN
    (tail -f $AUTH_STDIN & echo $! > $TAIL_PID) | bazel run :auth &
    export REGISTRY_PID=$!
    export TAIL_PID=$(cat $TAIL_PID)

    while ! nc -z localhost 1447; do   
      sleep 0.1
    done
    
    bazel run :push -- --repository localhost:1447/empty_image
}

function teardown_file() {
    bazel shutdown
    kill $REGISTRY_PID
    kill $TAIL_PID
}

function setup() {
    export DOCKER_CONFIG=$(mktemp -d)
}

function update_assert() {
    echo $@ > $AUTH_STDIN
    sleep 0.5
}

@test "plain text" {
    cat > "$DOCKER_CONFIG/config.json" <<EOF
{
  "auths": {
    "localhost:1447": { "username": "test", "password": "test" }
  }
}
EOF
    update_assert '{"Authorization": ["Basic dGVzdDp0ZXN0"]}'
    run bazel build @empty_image//... --repository_cache=$BATS_TEST_TMPDIR
    assert_success
}

@test "plain text base64" {
    cat > "$DOCKER_CONFIG/config.json" <<EOF
{
  "auths": {
    "http://localhost:1447": { "auth": "dGVzdDp0ZXN0" }
  }
}
EOF
    update_assert '{"Authorization": ["Basic dGVzdDp0ZXN0"]}'
    run bazel build @empty_image//... --repository_cache=$BATS_TEST_TMPDIR
    assert_success
}

@test "plain text https" {
    cat > "$DOCKER_CONFIG/config.json" <<EOF
{
  "auths": {
    "https://localhost:1447": { "username": "test", "password": "test" }
  }
}
EOF
    update_assert '{"Authorization": ["Basic dGVzdDp0ZXN0"]}'
    run bazel build @empty_image//... --repository_cache=$BATS_TEST_TMPDIR
    assert_success
}

@test "credstore" {
    cat > "$DOCKER_CONFIG/config.json" <<EOF
{
  "auths": { "localhost:1447": {} },
  "credsStore": "oci"
}
EOF
    update_assert '{"Authorization": ["Basic dGVzdGluZzpvY2k="]}'
    run bazel build @empty_image//... --repository_cache=$BATS_TEST_TMPDIR
    assert_success
}

@test "credstore misbehaves" {
    cat > "$DOCKER_CONFIG/config.json" <<EOF
{
  "auths": { "localhost:1447": {} },
  "credsStore": "evil"
}
EOF
    run bazel build @empty_image//... --repository_cache=$BATS_TEST_TMPDIR
    assert_failure
    assert_output -p "can't run at this time" "ERROR: credential helper failed:"
}

@test "credstore missing" {
    cat > "$DOCKER_CONFIG/config.json" <<EOF
{
  "auths": { "localhost:1447": {} },
  "credsStore": "missing"
}
EOF
    run bazel build @empty_image//... --repository_cache=$BATS_TEST_TMPDIR
    assert_failure
    assert_output -p "exec: docker-credential-missing: not found" "ERROR: credential helper failed:"
}