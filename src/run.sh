#!/bin/bash

set -e

RUN=0

STEP1="Step1.drep"
STEP2="Step2.mash"
STEP3="Step3.clusters"
STEP4="Step4.mmseqs"
STEP5="Step5.gtdbtk"
STEP6="Step6.annotation"
STEP6a="Step6a.sanntis"
STEP7="Step7.metadata"
STEP8="Step8.postprocessing"
STEP9="Step9.databases"
STEP10="Step10.restructure"

MEM_STEP1="50G"
MEM_STEP2="10G"
MEM_STEP3="50G"
MEM_STEP4="150G"
MEM_STEP5="500G"
MEM_STEP6="50G"
MEM_STEP6a="5G"
MEM_STEP7="5G"
MEM_STEP8="5G"
MEM_STEP9="150G" # kraken needs 150G

THREADS_STEP1="16"
THREADS_STEP2="4"
THREADS_STEP3="8"
THREADS_STEP4="32"
THREADS_STEP5="32"
THREADS_STEP6="16"
THREADS_STEP6a="1"
THREADS_STEP7="1"
THREADS_STEP8="1"
THREADS_STEP9="16"

usage() {
    cat <<EOF
usage: $0 options
Generate the genomes-pipeline bsub submission scripts.
The generated scripts will run the pipeline step by step using cwltool / toil.
Use the -r option to generate and run the scripts (using bwait between steps).

OPTIONS:
   -h      Show help message
   -t      Threads. Default=4 [OPTIONAL]
   -n      Catalogue name
   -o      Output location
   -f      Folder with ENA genomes
   -c      ENA genomes csv
   -x      Min MGYG
   -m      Max MGYG
   -v      Catalogue version
   -b      Catalogue Biome
   -r      Run the generated bsub scripts
EOF
}

while getopts "h:n:f:c:m:x:v:b:o:q:r" OPTION; do
    case $OPTION in
    h)
        usage
        exit 1
        ;;
    n)
        NAME=${OPTARG}
        ;;
    f)
        ENA_GENOMES=${OPTARG}
        ;;
    c)
        ENA_CSV=${OPTARG}
        ;;
    m)
        MAX_MGYG=${OPTARG}
        ;;
    x)
        MIN_MGYG=${OPTARG}
        ;;
    v)
        CATALOGUE_VERSION=${OPTARG}
        ;;
    b)
        BIOM=${OPTARG}
        ;;
    o)
        OUTPUT=${OPTARG}
        ;;
    q)
        QUEUE=${OPTARG}
        ;;
    r)
        RUN=1
        ;;
    ?)
        usage
        exit 1
        ;;
    esac
done

if [[ -z ${NAME} ]]; then
    NAME="genomes-annontation-test"
fi

if [[ -z ${OUTPUT} ]]; then
    OUTPUT=${PIPELINE_DIRECTORY}
fi

if [[ -z ${CATALOGUE_VERSION} ]]; then
    CATALOGUE_VERSION="v1.0"
fi

if [[ -z ${QUEUE} ]]; then
    QUEUE=${DEFAULT_QUEUE}
fi

OUT=${OUTPUT}/${NAME}
LOGS=${OUT}/logs/

YML=${OUT}/ymls

SUBMIT_SCRIPTS=${OUT}/scripts

mkdir -p "${OUT}" "${LOGS}" "${YML}" "${SUBMIT_SCRIPTS}"

REPS_FILE=${OUT}/cluster_reps.txt
ALL_GENOMES=${OUT}/drep-filt-list.txt

touch "${REPS_FILE}" "${ALL_GENOMES}"

REPS_FA_DIR=${OUT}/reps_fa
ALL_FNA_DIR=${OUT}/mgyg_genomes

MEM="10G"
THREADS="2"

# ------------------------- Step 1 -------------------------------------------------
echo "==== 1. dRep steps with cwltool [${SUBMIT_SCRIPTS}/step1.${NAME}.sh] ===="

# TODO improve for NCBI
cat <<EOF >${SUBMIT_SCRIPTS}/step1.${NAME}.sh
#!/bin/bash

bash ${PIPELINE_DIRECTORY}/src/steps/1_drep.sh \\
    -o ${OUT} \\
    -p ${PIPELINE_DIRECTORY} \\
    -l ${LOGS} \\
    -n ${NAME} \\
    -q ${QUEUE} \\
    -y ${YML} \\
    -i "${ENA_GENOMES}" \\
    -c "${ENA_CSV}" \\
    -m "${MAX_MGYG}" \\
    -x "${MIN_MGYG}" \\
    -j ${STEP1} \\
    -z ${MEM_STEP1} \\
    -t ${THREADS_STEP1}
EOF

if [[ $RUN == 1 ]]; then
    echo "Running dRep [${SUBMIT_SCRIPTS}/step1.${NAME}.sh]"
    bash "${SUBMIT_SCRIPTS}"/step1.${NAME}.sh
    sleep 10 # let's give LSF time to catch up
    bwait -w "ended(${STEP1}.${NAME})"
fi

# ------------------------- Step 2 ------------------------------------
echo "==== 2. mash2nwk submission script [${SUBMIT_SCRIPTS}/step2.${NAME}.sh] ===="

cat <<EOF >${SUBMIT_SCRIPTS}/step2.${NAME}.sh
#!/bin/bash

bsub \\
    -J "${STEP2}.${NAME}.submit" \\
    -q ${QUEUE} \\
    -e ${LOGS}/submit.${STEP2}.err \\
    -o ${LOGS}/submit.${STEP2}.out \\
    bash ${PIPELINE_DIRECTORY}/src/steps/2_mash.sh \\
        -m ${OUT}/${NAME}_drep/mash \\
        -o ${OUT} \\
        -p ${PIPELINE_DIRECTORY} \\
        -l ${LOGS} \\
        -n ${NAME} \\
        -q ${QUEUE} \\
        -y ${YML} \\
        -j ${STEP2} \\
        -z ${MEM_STEP2} \\
        -t ${THREADS_STEP2}
EOF

if [[ $RUN == 1 ]]; then
    echo "Running mash2nwk ${SUBMIT_SCRIPTS}/step2.${NAME}.sh"
    bash ${SUBMIT_SCRIPTS}/step2.${NAME}.sh
fi

# ------------------------- Step 3 ------------------------------
mkdir -p ${OUT}/sg ${OUT}/pg
echo "==== 3. Cluster annotation [${SUBMIT_SCRIPTS}/step3.${NAME}.sh] ===="

#########
## ENV ##
####################################
# GUNC_DB needs to be set in .gpenv
####################################

cat <<EOF >${SUBMIT_SCRIPTS}/step3.${NAME}.sh
#!/bin/bash

bsub \\
    -J "${STEP3}.${NAME}.sg" \\
    -q ${QUEUE} \\
    -e ${LOGS}/submit.${STEP3}.sg.err \\
    -o ${LOGS}/submit.${STEP3}.sg.out \\
    bash ${PIPELINE_DIRECTORY}/src/steps/3_process_clusters.sh \\
        -i ${OUT}/${NAME}_drep/singletons \\
        -o ${OUT} \\
        -p ${PIPELINE_DIRECTORY} \\
        -t "sg" \\
        -l ${LOGS} \\
        -n ${NAME} \\
        -q ${QUEUE} \\
        -y ${YML} \\
        -j ${STEP3} \\
        -s "${ENA_CSV}" \\
        -z ${MEM_STEP3} \\
        -w ${THREADS_STEP3} \\
        -g ${GUNC_DB}

bsub \\
    -J "${STEP3}.${NAME}.pg" \\
    -q ${QUEUE} \\
    -e ${LOGS}/submit.${STEP3}.pg.err \\
    -o ${LOGS}/submit.${STEP3}.pg.out \\
    bash ${PIPELINE_DIRECTORY}/src/steps/3_process_clusters.sh \\
        -i ${OUT}/${NAME}_drep/pan-genomes \\
        -o ${OUT} \\
        -p ${PIPELINE_DIRECTORY} \\
        -t "pg" \\
        -l ${LOGS} \\
        -n ${NAME} \\
        -q ${QUEUE} \\
        -y ${YML} \\
        -j ${STEP3} \\
        -s "${ENA_CSV}" \\
        -z ${MEM_STEP3} \\
        -w ${THREADS_STEP3} \\
        -g ${GUNC_DB}
EOF

if [[ $RUN == 1 ]]; then
    echo "==== Running step 3 ===="
    bwait -w "ended(${STEP2}.${NAME}.*)"
    echo "Running Cluster annotation [${SUBMIT_SCRIPTS}/step3.${NAME}.sh]"
    bash ${SUBMIT_SCRIPTS}/step3.${NAME}.sh
fi

# ------------------------- Step 4 ------------------------------

echo "==== 4. mmseqs [${SUBMIT_SCRIPTS}/step4.${NAME}.sh] ===="

cat <<EOF >${SUBMIT_SCRIPTS}/step4.${NAME}.sh
#!/bin/bash

bsub \\
    -J "${STEP4}.${NAME}.submit" \\
    -q ${QUEUE} \\
    -e ${LOGS}/submit.${STEP4}.err \\
    -o ${LOGS}/submit.${STEP4}.out \\
    bash ${PIPELINE_DIRECTORY}/src/steps/4_mmseqs.sh \\
        -o ${OUT} \\
        -p ${PIPELINE_DIRECTORY} \\
        -l ${LOGS} \\
        -n ${NAME} \\
        -q ${QUEUE} \\
        -y ${YML} \\
        -j ${STEP4} \\
        -r ${REPS_FILE} \\
        -f ${ALL_GENOMES} \\
        -a ${REPS_FA_DIR} \\
        -k ${ALL_FNA_DIR} \\
        -d ${OUT}/${NAME}_drep \\
        -z ${MEM_STEP4} \\
        -t ${THREADS_STEP4}
EOF

if [[ $RUN == 1 ]]; then
    echo "==== Running step 4 [${SUBMIT_SCRIPTS}/step4.${NAME}.sh] ===="
    echo "===== waiting for cluster annotations (step3).... ===="
    bwait -w "ended(${STEP3}.${NAME}.*)"
    bash ${SUBMIT_SCRIPTS}/step4.${NAME}.sh
fi

# ------------------------- Step 5 ------------------------------
echo "==== 5. GTDB-Tk [${SUBMIT_SCRIPTS}/step5.${NAME}.sh] ===="

if [[ $RUN == 1 ]]; then
    echo "==== waiting for files/folders generation.... ===="
    bwait -w "ended(${STEP4}.${NAME}.submit)"
    bwait -w "ended(${STEP4}.${NAME}.files)"
fi

#########
## ENV ##
#######################################
# GTDBTK_REF needs to be set in .gpenv
########################################

# TODO change queue to BIGMEM in production
cat <<EOF >${SUBMIT_SCRIPTS}/step5.${NAME}.sh
#!/bin/bash

bsub \\
    -J "${STEP5}.${NAME}.submit" \\
    -q ${QUEUE} \\
    -o ${LOGS}/submit.${STEP5}.out \\
    -e ${LOGS}/submit.${STEP5}.err \\
    bash ${PIPELINE_DIRECTORY}/src/steps/5_gtdbtk.sh \\
        -q ${BIGQUEUE} \\
        -p ${PIPELINE_DIRECTORY} \\
        -o ${OUT} \\
        -l ${LOGS} \\
        -n ${NAME} \\
        -y ${YML} \\
        -j ${STEP5} \\
        -a ${REPS_FA_DIR} \\
        -z ${MEM_STEP5} \\
        -t ${THREADS_STEP5} \\
        -r ${GTDBTK_REF}

EOF

if [[ $RUN == 1 ]]; then
    echo "==== Running step 5 [${SUBMIT_SCRIPTS}/step5.${NAME}.sh] ===="
    bash ${SUBMIT_SCRIPTS}/step5.${NAME}.sh
    bwait -w "ended(${STEP4}.${NAME}.cat) && ended(${STEP4}.${NAME}.yml.*)"
fi

# ------------------------- Step 6 ------------------------------
if [[ $RUN == 1 ]]; then
    echo "==== waiting for mmseqs 0.9.... ===="
    bwait -w "ended(${STEP4}.${NAME}.0.90)"
fi

echo "==== 6. EggNOG, IPS, rRNA [${SUBMIT_SCRIPTS}/step6.${NAME}.sh] ===="

cat <<EOF >${SUBMIT_SCRIPTS}/step6.${NAME}.sh
#!/bin/bash

bsub \\
    -J "${STEP6}.${NAME}.submit" \\
    -q ${QUEUE} \\
    -e ${LOGS}/submit.${STEP6}.err \\
    -o ${LOGS}/submit.${STEP6}.out \\
    bash ${PIPELINE_DIRECTORY}/src/steps/6_annotation.sh \\
        -o ${OUT} \\
        -p ${PIPELINE_DIRECTORY} \\
        -l ${LOGS} \\
        -n ${NAME} \\
        -q ${QUEUE} \\
        -y ${YML} \\
        -i ${OUT}/${NAME}_mmseqs_0.90/mmseqs_0.9_outdir \\
        -r ${REPS_FILE} \\
        -j ${STEP6} \\
        -b ${ALL_FNA_DIR} \\
        -z ${MEM_STEP6} \\
        -t ${THREADS_STEP6} \\
        -w "True"
EOF

if [[ $RUN == 1 ]]; then
    echo "==== Running step 6 [${SUBMIT_SCRIPTS}/step6.${NAME}.sh] ===="
fi

# ------------------------- Step 6a ------------------------------
echo "==== 6a. Sanntis [${SUBMIT_SCRIPTS}/step6a.${NAME}.sh] ===="

cat <<EOF >${SUBMIT_SCRIPTS}/step6a.${NAME}.sh
#!/bin/bash
bsub \\
    -J "${STEP6a}.${NAME}.submit" \\
    -q ${QUEUE} \\
    -e ${LOGS}/submit.${STEP6a}.err \\
    -o ${LOGS}/submit.${STEP6a}.out \\
    bash ${PIPELINE_DIRECTORY}/src/steps/6a_run_sanntis.sh \\
        -o ${OUT} \\
        -l ${LOGS} \\
        -n ${NAME} \\
        -q ${QUEUE} \\
        -j ${STEP6a} \\
        -z ${MEM_STEP6a} \\
        -t ${THREADS_STEP6a}
EOF

# ------------------------- Step 7 ------------------------------
if [[ $RUN == 1 ]]; then
    echo "==== waiting for GTDB-Tk.... ===="
    bwait -w "ended(${STEP5}.${NAME}.submit) && ended(${STEP6}.${NAME}.submit)"
    bwait -w "ended(${STEP5}.${NAME}.run) && ended(${STEP6}.${NAME}.run)"
fi

echo "==== 7. Metadata and phylo.tree [${SUBMIT_SCRIPTS}/step7.${NAME}.sh] ===="

cat <<EOF >${SUBMIT_SCRIPTS}/step7.${NAME}.sh
#!/bin/bash

bsub \\
    -J "${STEP7}.${NAME}.submit" \\
    -q ${QUEUE} \\
    -e ${LOGS}/submit.${STEP7}.err \\
    -o ${LOGS}/submit.${STEP7}.out \\
    bash ${PIPELINE_DIRECTORY}/src/steps/7_metadata.sh \\
        -o ${OUT} \\
        -p ${PIPELINE_DIRECTORY} \\
        -l ${LOGS} \\
        -n ${NAME} \\
        -q ${QUEUE} \\
        -y ${YML} \\
        -v ${CATALOGUE_VERSION} \\
        -i ${OUT}/${NAME}_drep/intermediate_files \\
        -g ${OUT}/gtdbtk/gtdbtk-outdir \\
        -r ${OUT}/${NAME}_annotations/rRNA_outs \\
        -j ${STEP7} \\
        -f ${ALL_FNA_DIR} \\
        -s "${ENA_CSV}" \\
        -z ${MEM_STEP7} \\
        -d ${GEO} \\
        -t ${THREADS_STEP7}
EOF

if [[ $RUN == 1 ]]; then
    echo "==== Running step 7 [${SUBMIT_SCRIPTS}/step7.${NAME}.sh] ===="
    bash ${SUBMIT_SCRIPTS}/step7.${NAME}.sh
    sleep 10
    echo "==== waiting for metadata and protein annotations.... ===="
    bwait -w "ended(${STEP6}.${NAME}.submit) && ended(${STEP7}.${NAME}.submit)"
    bwait -w "ended(${STEP6}.${NAME}.run) && ended(${STEP7}.${NAME}.run)"
fi

# ------------------------- Step 8 ------------------------------
echo "==== 8. Post-processing [${SUBMIT_SCRIPTS}/step8.${NAME}.sh] ===="

cat <<EOF >${SUBMIT_SCRIPTS}/step8.${NAME}.sh
#!/bin/bash

bsub \\
    -J "${STEP8}.${NAME}.submit" \\
    -q ${QUEUE} \\
    -e ${LOGS}/submit.${STEP8}.err \\
    -o ${LOGS}/submit.${STEP8}.out \\
    bash ${PIPELINE_DIRECTORY}/src/steps/8_post_processing.sh \\
        -o ${OUT} \\
        -p ${PIPELINE_DIRECTORY} \\
        -l ${LOGS} \\
        -n ${NAME} \\
        -q ${QUEUE} \\
        -j ${STEP8} \\
        -b "${BIOM}" 
EOF

if [[ $RUN == 1 ]]; then
    echo "==== Running step 8 [${SUBMIT_SCRIPTS}/step8.${NAME}.sh] ===="
    bash ${SUBMIT_SCRIPTS}/step8.${NAME}.sh
    sleep 10
    echo "==== waiting for post-processing ===="
    bwait -w "ended(${STEP8}.${NAME}.submit)"
    bwait -w "ended(${STEP8}.${NAME}.run)"
fi

# ------------------------- Step 9 -------------------------------
echo "==== 9. Databases [${SUBMIT_SCRIPTS}/step9.${NAME}.sh] ===="

cat <<EOF >${SUBMIT_SCRIPTS}/step9.${NAME}.sh
#!/bin/bash
bsub \\
    -J "${STEP9}.${NAME}.submit" \\
    -q ${QUEUE} \\
    -e ${LOGS}/submit.${STEP9}.err \\
    -o ${LOGS}/submit.${STEP9}.out \\
    bash ${PIPELINE_DIRECTORY}/src/steps/9_databases.sh \\
        -o ${OUT} \\
        -p ${PIPELINE_DIRECTORY} \\
        -l ${LOGS} \\
        -n ${NAME} \\
        -q ${QUEUE} \\
        -j ${STEP9} \\
        -v ${CATALOGUE_VERSION} \\
        -z ${MEM_STEP9} \\
        -t ${THREADS_STEP9}
EOF

# ------------------------- Step 10 ------------------------------

echo "==== 10. Re-structure [${SUBMIT_SCRIPTS}/step10.${NAME}.sh] ===="

cat <<EOF >${SUBMIT_SCRIPTS}/step10.${NAME}.sh
#!/bin/bash
bsub \\
    -J "${STEP10}.${NAME}.submit" \\
    -q ${QUEUE} \\
    -e ${LOGS}/submit.${STEP10}.err \\
    -o ${LOGS}/submit.${STEP10}.out \\
    bash ${PIPELINE_DIRECTORY}/src/steps/10_restructure.sh \\
        -o ${OUT} \\
        -n ${NAME}
EOF

echo "==== Final. Exit ===="