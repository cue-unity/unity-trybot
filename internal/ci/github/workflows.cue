// Copyright 2021 The CUE Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package github

import (
	"github.com/SchemaStore/schemastore/src/schemas/json"
)

workflowsDir: *"./" | string @tag(workflowsDir)

_#mainBranch:        "main"
_#releaseTagPattern: "v*"

workflows: [...{file: string, schema: (json.#Workflow & {})}]
workflows: [
	{
		file:   "trybot.yml"
		schema: trybot
	},
	{
		file:   "daily_check.yml"
		schema: daily_check
	},
	{
		file:   "unity.yml"
		schema: unity
	},
]

_#bashWorkflow: json.#Workflow & {
	jobs: [string]: defaults: run: shell: "bash"
}

// TODO: drop when cuelang.org/issue/390 is fixed.
// Declare definitions for sub-schemas
_#job:  ((json.#Workflow & {}).jobs & {x: _}).x
_#step: ((_#job & {steps:                 _}).steps & [_])[0]

// Use a specific latest version for release builds
_#latestStableGo: "1.18.x"
_#codeGenGo:      _#latestStableGo

_#linuxMachine:   "ubuntu-20.04"
_#macosMachine:   "macos-11"
_#windowsMachine: "windows-2022"

_#writeNetrcFile: _#step & {
	name: "Write netrc file for cueckoo Gerrithub"
	run: """
		cat <<EOD > ~/.netrc
		machine review.gerrithub.io
		login cueckoo
		password ${{ secrets.CUECKOO_GERRITHUB_PASSWORD }}
		EOD
		chmod 600 ~/.netrc
		"""
}

_#testStrategy: {
	"fail-fast": false
	matrix: {
		"go-version": [_#latestStableGo]
		os: [_#linuxMachine]
	}
}

_#setGoBuildTags: _#step & {
	_#tags: string
	name:   "Set go build tags"
	run:    """
		go env -w GOFLAGS=-tags=\(_#tags)
		"""
}

_#installGo: _#step & {
	name: "Install Go"
	uses: "actions/setup-go@v2"
	with: {
		"go-version": *"${{ matrix.go-version }}" | string
		stable:       false
	}
}

_#checkoutCode: _#step & {
	name: "Checkout code"
	uses: "actions/checkout@v2"
	with: {
		submodules: true
	}
}

_#cacheGoModules: _#step & {
	name: "Cache Go modules"
	uses: "actions/cache@v1"
	with: {
		path: "~/go/pkg/mod"
		key:  "${{ runner.os }}-${{ matrix.go-version }}-go-${{ hashFiles('**/go.sum') }}"
		"restore-keys": """
			${{ runner.os }}-${{ matrix.go-version }}-go-
			"""
	}
}

_#goModVerify: _#step & {
	name: "go mod verify"
	run:  "go mod verify"
}

_#goModTidy: _#step & {
	name: "go mod tidy"
	run:  "go mod tidy"
}

_#goGenerate: _#step & {
	name: "Generate"
	run:  "go generate ./..."
	// The Go version corresponds to the precise version specified in
	// the matrix. Skip windows for now until we work out why re-gen is flaky
	if: "matrix.go-version == '\(_#codeGenGo)' && matrix.os != '\(_#windowsMachine)'"
}

_#staticcheck: _#step & {
	name: "staticcheck"
	run:  "go run honnef.co/go/tools/cmd/staticcheck@v0.3.2 ./..."
}

_#goTest: _#step & {
	name: "Test"
	run:  "go test -count=1 ./..."
}

_#goTestRace: _#step & {
	name: "Test with -race"
	run:  "go test -count=1 -race ./..."
}

_#checkGitClean: _#step & {
	name: "Check that git is clean post generate and tests"
	run:  "test -z \"$(git status --porcelain)\" || (git status; git diff; false)"
}

_#installUnity: _#step & {
	name: "Install unity"
	run:  "./_scripts/installUnity.sh"
}

_#runUnity: _#step & {
	name: "Run unity"
	run:  "./_scripts/runUnity.sh"
}

_#branchRefPrefix: "refs/heads/"

// _#isCLCITestBranch is an expression that evaluates to true
// if the job is running as a result of a CL triggered CI build
_#isCLCITestBranch: "startsWith(github.ref, '\(_#branchRefPrefix)ci/')"

// _#isMain is an expression that evaluates to true if the
// job is running as a result of a main commit push
_#isMain: "github.ref == '\(_#branchRefPrefix+_#mainBranch)'"
