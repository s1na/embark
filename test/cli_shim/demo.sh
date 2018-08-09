#!/usr/bin/env bash

reset_shim_demo() {
    local EMBARK_DOCKER_IMAGE="${EMBARK_DOCKER_IMAGE:-michaelsbradleyjr/embark}"
    # ^ once the PR is ready to merge this should be bumped to :-statusim/embark
    # ^ pending embark@3.1.8 being published, and image for it pushed to docker
    #   hub
    local EMBARK_DOCKER_TAG="${EMBARK_DOCKER_TAG:-latest}"
    local EMBARK_DOCKERFILE="${EMBARK_DOCKERFILE}"
    local shim_demo_tag
    if [[ (! -z "$EMBARK_DOCKERFILE") \
              && "$EMBARK_DOCKER_TAG" = "latest" ]]; then
        shim_demo_tag="shim-demo"
    else
        shim_demo_tag="${EMBARK_DOCKER_TAG}-shim-demo"
    fi
    local step
    if [[ -z "$1" ]]; then
        step="step-0"
    else
        step="$1"
    fi
    docker rmi "${EMBARK_DOCKER_IMAGE}:${shim_demo_tag}-${step}" &> /dev/null
}
export -f reset_shim_demo

run_shim_demo () {
    local EMBARK_BRANCH="${EMBARK_BRANCH:-features/global-local-cmd-shim}"
    # ^ once the PR is ready to merge this should be bumped to :-develop
    local EMBARK_DOCKER_IMAGE="${EMBARK_DOCKER_IMAGE:-michaelsbradleyjr/embark}"
    # ^ once the PR is ready to merge this should be bumped to :-statusim/embark
    # ^ pending embark@3.1.8 being published, and image for it pushed to docker
    #   hub
    local EMBARK_DOCKER_RUN
    local EMBARK_DOCKER_RUN_INTERACTIVE
    local EMBARK_DOCKER_RUN_OPTS_REPLACE
    local EMBARK_DOCKER_RUN_RM
    local EMBARK_DOCKER_TAG="${EMBARK_DOCKER_TAG:-latest}"
    local EMBARK_DOCKERFILE="${EMBARK_DOCKERFILE}"
    # ^ can override with local /path/to/embark-docker/ or a url such as:
    #   https://github.com/embark-framework/embark-docker.git#master
    # ^ if this env var is not empty, it will trigger `docker build` instead of
    #   `docker pull` in step-0
    local EMBARK_SHIM_DEMO_DEV=${EMBARK_SHIM_DEMO_DEV:-false}
    local EMBARK_VERSION="${EMBARK_VERSION:-embark-framework/embark#${EMBARK_BRANCH}}"
    # ^ only kicks in for `docker build`, not `docker pull`
    local REAL="${REAL:-https://gist.githubusercontent.com/michaelsbradleyjr/87b5a99ad551e04cbad9c0c1d3af412b/raw/bfec2e589a91302b30f1d7cac8c2df71e5ebabe0/real.sh}"
    local RUNNER="${RUNNER:-https://raw.githubusercontent.com/embark-framework/embark-docker/master/run.sh}"
    # ^ for local fs override spec URL with file:///path/to/run.sh

    local shim_demo_tag
    if [[ (! -z "$EMBARK_DOCKERFILE") \
              && "$EMBARK_DOCKER_TAG" = "latest" ]]; then
        shim_demo_tag="shim-demo"
    else
        shim_demo_tag="${EMBARK_DOCKER_TAG}-shim-demo"
    fi
    local __shim_demo_tag="$shim_demo_tag"
    local was_reset=false
    local work_dir="$PWD"
    source <(curl "$REAL" 2> /dev/null)
    local script_dir="$(real_dir "$BASH_SOURCE")"
    local embark_dir="$(real_dir "$script_dir/../..")"
    local cid_file="$script_dir/.cid"
    source <(curl "$RUNNER" 2> /dev/null)

    __check_image () {
        local tag
        if [[ -z "$1" ]]; then
            tag="$shim_demo_tag"
        else
            tag="${__shim_demo_tag}-$1"
        fi
        local iid="$(docker images -q ${EMBARK_DOCKER_IMAGE}:${tag} 2> /dev/null)"
        if [[ "$iid" = "" ]]; then
            return 1
        fi
    }

    __return () {
        local retval=$?
        unset __check_image
        unset __return
        rm -f "$cid_file"
        cd "$work_dir"
        return $retval
    }

    # -- step 0 ----------------------------------------------------------------

    echo '-----------------------------------'
    echo 'setup - STEP 0'
    echo '-----------------------------------'

    shim_demo_tag="${__shim_demo_tag}-step-0"
    if ! __check_image; then
        was_reset=true
        if [[ ! -z "$EMBARK_DOCKERFILE" ]]; then
            docker build \
                   --build-arg EMBARK_VERSION="$EMBARK_VERSION" \
                   -t "${EMBARK_DOCKER_IMAGE}:${EMBARK_DOCKER_TAG}" \
                   "$EMBARK_DOCKERFILE" \
                   || __return || return
        else
            docker pull "${EMBARK_DOCKER_IMAGE}:${EMBARK_DOCKER_TAG}" \
                || __return || return
        fi
        docker tag \
               "${EMBARK_DOCKER_IMAGE}:${EMBARK_DOCKER_TAG}" \
               "${EMBARK_DOCKER_IMAGE}:${shim_demo_tag}" \
            || __return || return
    else
        echo "cached..."
    fi

    # -- step 1 ----------------------------------------------------------------

    echo '-----------------------------------'
    echo 'setup - STEP 1'
    echo '-----------------------------------'

    if (! __check_image step-1) || [[ $was_reset = true ]]; then
        was_reset=true
        rm -f "$cid_file"
        EMBARK_DOCKER_TAG="$shim_demo_tag" \
                         run_embark \
                         --cidfile "$cid_file" \
                         -d \
                         -- bash -c 'trap "exit 0" SIGINT && while true; do sleep 1; done' \
            || __return || return
        docker exec \
               -it \
               $(cat "$cid_file") \
               bash -c 'apt-get update && apt-get install -y rsync' \
            || __return || return
        shim_demo_tag="${__shim_demo_tag}-step-1"
        docker commit \
               --pause \
               $(cat "$cid_file") \
               "${EMBARK_DOCKER_IMAGE}:${shim_demo_tag}" \
            || __return || return
        docker stop $(cat "$cid_file") \
            || __return || return
        rm -f "$cid_file"
    else
        shim_demo_tag="${__shim_demo_tag}-step-1"
        echo "cached..."
    fi

    # -- step 2 ----------------------------------------------------------------

    echo '-----------------------------------'
    echo 'setup - STEP 2'
    echo '-----------------------------------'

    local td_dapp="${HOME}/temp/$(basename $(mktemp -d))"
    mkdir -p "$td_dapp"

    if (! __check_image step-2) || [[ $was_reset = true ]]; then
        was_reset=true
        rm -f "$cid_file"
        # do not alter indentation, tabs in lines below
        local step_2=$(cat <<- 'SCRIPT'
	#!/bin/bash
	simple_nodeenv 8.11.2 pre-lts-newer-npm
	npm install -g npm@6.2.0
	simple_nodeenv 8.11.3 lts-older-npm
	simple_nodeenv 8.11.3 lts
	npm install -g npm@6.2.0
	npm install -g json
	nac default
	SCRIPT
        )
        # do not alter indentation, tabs in lines above
        cd "$td_dapp"
        EMBARK_DOCKER_RUN_RM=false
        EMBARK_DOCKER_RUN=<(echo "$step_2") \
                         EMBARK_DOCKER_TAG="$shim_demo_tag" \
                         run_embark \
                         --cidfile "$cid_file" \
                         -- \
            || __return || return
        EMBARK_DOCKER_RUN_RM=true
        shim_demo_tag="${__shim_demo_tag}-step-2"
        docker commit $(cat "$cid_file") "${EMBARK_DOCKER_IMAGE}:${shim_demo_tag}" \
            || __return || return
        docker rm $(cat "$cid_file") \
            || __return || return
        rm -f "$cid_file"
        cd "$work_dir"
    else
        shim_demo_tag="${__shim_demo_tag}-step-2"
        echo "cached..."
    fi

    # -- step 3 ----------------------------------------------------------------

    echo '-----------------------------------'
    echo 'setup - STEP 3'
    echo '-----------------------------------'

    if (! __check_image step-3) || [[ $was_reset = true ]]; then
        was_reset=true
        rm -f "$cid_file"
        # do not alter indentation, tabs in lines below
        local step_3=$(cat <<- 'SCRIPT'
	#!/bin/bash
	dev=$1
	embark_branch="$2"
	if [[ "$dev" = false ]]; then
	    mkdir -p ~/repos/embark
	    git clone https://github.com/embark-framework/embark.git \
	              ~/repos/embark
	    cd ~/repos/embark \
	        && git checkout "$embark_branch" \
	        && cd - &> /dev/null
	fi
	mkdir -p ~/working/embark
	rsync -a \
	      --exclude=.git \
	      --exclude=node_modules \
	      --exclude=test/cli_shim/.cid \
	      ~/repos/embark \
	      ~/working/
	cd ~/working/embark
	git config --global user.email "foo@bar"
	git config --global user.name "Foo Bar"
	git init
	git add -A
	git commit -m 'synced!'
	nac lts
	npm install
	npm link
	cd - &> /dev/null
	nac default
	SCRIPT
        )
        # do not alter indentation, tabs in lines above
        cd "$td_dapp"
        local -a run_opts_step_3=(
            "--cidfile"
            "$cid_file"
        )
        if [[ $EMBARK_SHIM_DEMO_DEV = true ]]; then
            run_opts_step_3=(
                "${run_opts_step_3[@]}"
                "-v"
                "${embark_dir}:/home/embark/repos/embark"
            )
        fi
        EMBARK_DOCKER_RUN_RM=false
        EMBARK_DOCKER_RUN=<(echo "$step_3") \
                         EMBARK_DOCKER_TAG="$shim_demo_tag" \
                         run_embark \
                         "${run_opts_step_3[@]}" \
                         -- \
                         $EMBARK_SHIM_DEMO_DEV \
                         "$EMBARK_BRANCH" \
            || __return || return
        EMBARK_DOCKER_RUN_RM=true
        shim_demo_tag="${__shim_demo_tag}-step-3"
        docker commit $(cat "$cid_file") "${EMBARK_DOCKER_IMAGE}:${shim_demo_tag}" \
            || __return || return
        docker rm $(cat "$cid_file") \
            || __return || return
        rm -f "$cid_file"
        cd "$work_dir"
    else
        shim_demo_tag="${__shim_demo_tag}-step-3"
        echo "cached..."
    fi

    # -- step 4 ----------------------------------------------------------------

    echo '-----------------------------------'
    echo 'setup - STEP 4'
    echo '-----------------------------------'

    if (! __check_image step-4) || [[ $was_reset = true ]]; then
        was_reset=true
        rm -f "$cid_file"
        # do not alter indentation, tabs in lines below
        local step_4=$(cat <<- 'SCRIPT'
	#!/bin/bash
	dev=$1
	if [[ "$dev" = true ]]; then
	    rsync -a \
	          --exclude=.git \
	          --exclude=node_modules \
	          --exclude=test/cli_shim/.cid \
	          ~/repos/embark \
	          ~/working/
	fi
	cd ~/working/embark
	git add -A
	git commit -m 'synced!'
	cd - &> /dev/null
	cd ~
	nac default
	embark demo
	cd - &> /dev/null
	cd ~/embark_demo
	if [[ ! -f .gitignore ]]; then
	    cat << GITIGNORE > .gitignore
	.embark/
	node_modules/
	dist/
	config/production/password
	config/livenet/passwordp
	GITIGNORE
	fi
	git init
	git add -A
	git commit -m 'synced!'
	cd - &> /dev/null
	SCRIPT
        )
        # do not alter indentation, tabs in lines above
        cd "$td_dapp"
        local -a run_opts_step_4=(
            "--cidfile"
            "$cid_file"
        )
        if [[ $EMBARK_SHIM_DEMO_DEV = true ]]; then
            run_opts_step_4=(
                "${run_opts_step_4[@]}"
                "-v"
                "${embark_dir}:/home/embark/repos/embark"
            )
        fi
        EMBARK_DOCKER_RUN_RM=false
        EMBARK_DOCKER_RUN=<(echo "$step_4") \
                         EMBARK_DOCKER_TAG="$shim_demo_tag" \
                         run_embark \
                         "${run_opts_step_4[@]}" \
                         -- \
                         $EMBARK_SHIM_DEMO_DEV \
            || __return || return
        EMBARK_DOCKER_RUN_RM=true
        shim_demo_tag="${__shim_demo_tag}-step-4"
        docker commit $(cat "$cid_file") "${EMBARK_DOCKER_IMAGE}:${shim_demo_tag}" \
            || __return || return
        docker rm $(cat "$cid_file") \
            || __return || return
        rm -f "$cid_file"
        cd "$work_dir"
    else
        shim_demo_tag="${__shim_demo_tag}-step-4"
        echo "cached..."
    fi

    # -- DEMO ------------------------------------------------------------------

    echo '-----------------------------------'
    echo 'DEMO'  🎉
    echo '-----------------------------------'

    # do not alter indentation, tabs in lines below
    local demo=$(cat <<- SCRIPT
	#!/bin/bash
	dev=\$1
	if [[ "\$dev" = true ]]; then
	    rsync -a \
	          --exclude=.git \
	          --exclude=node_modules \
	          --exclude=test/cli_shim/.cid \
	          ~/repos/embark \
	          ~/working/
	fi
	cd ~/working/embark
	git add -A
	git commit -m 'synced!'
	cd - &> /dev/null
	txtbld=\$(tput bold)
	txtrst=\$(tput sgr0)
	bldcyn=\${txtbld}\$(tput setaf 6)
	say () {
	    local msg="\$1"
	    msg="\$([[ "\$msg" =~ \
	              [[:space:]]*([^[:space:]]|[^[:space:]].*[^[:space:]])[[:space:]]* ]]; \
	              echo -n "\${BASH_REMATCH[1]}")"
	    echo
	    echo
	    echo "\${bldcyn}\${msg}\${txtrst}"
	}
	export -f say
	export PROMPT_COMMAND="echo; echo"
	# demos
	$(< "$script_dir/demos/pre-lts-newer-npm.sh")
	$(< "$script_dir/demos/lts-older-npm.sh")
	$(< "$script_dir/demos/pre-lts-runtime.sh")
	$(< "$script_dir/demos/global_missing_json.sh")
	$(< "$script_dir/demos/global_bad_json.sh")
	$(< "$script_dir/demos/global_no_version.sh")
	trap "exit 0" SIGINT && while true; do sleep 1; done
	SCRIPT
    )
    # do not alter indentation, tabs in lines above
    cd "$td_dapp"
    local -a run_opts_demo=()
    if [[ $EMBARK_SHIM_DEMO_DEV = true ]]; then
        run_opts_demo=(
            "${run_opts_demo[@]}"
            "-v"
            "${embark_dir}:/home/embark/repos/embark"
        )
    fi
    EMBARK_DOCKER_RUN=<(echo "$demo") \
                     EMBARK_DOCKER_TAG="$shim_demo_tag" \
                     run_embark \
                     "${run_opts_demo[@]}" \
                     -- \
                     $EMBARK_SHIM_DEMO_DEV \
        || __return || return
    cd "$work_dir"
}
export -f run_shim_demo

if [[ "$0" = "$BASH_SOURCE" ]]; then
    run_shim_demo
fi
