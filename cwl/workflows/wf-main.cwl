#!/usr/bin/env cwl-runner
cwlVersion: v1.2
class: Workflow

requirements:
  SubworkflowFeatureRequirement: {}
  MultipleInputFeatureRequirement: {}
  InlineJavascriptRequirement: {}
  StepInputExpressionRequirement: {}
  ScatterFeatureRequirement: {}

inputs:
  genomes_ena: Directory?
  ena_csv: File?
  genomes_ncbi: Directory?

  max_accession_mgyg: int
  min_accession_mgyg: int

  # skip dRep step if MAGs were already dereplicated
  skip_drep_step: boolean   # set True for skipping

  # no gtdbtk
  skip_gtdbtk_step: boolean   # set True for skipping

  # common input
  mmseqs_limit_c: float
  mmseqs_limit_i: float[]
  mmseq_limit_annotation: float

  gunc_db_path: File

  gtdbtk_data: Directory?

  interproscan_databases: [string, Directory]
  chunk_size_ips: int
  chunk_size_eggnog: int
  db_diamond_eggnog: [string?, File?]
  db_eggnog: [string?, File?]
  data_dir_eggnog: [string?, Directory?]

  cm_models: Directory

outputs:

# ------- unite_folders -------
  output_csv:
    type: File
    outputSource: unite_folders/csv

# ------- assign_mgygs -------
  renamed_csv:
    type: File
    outputSource: assign_mgygs/renamed_csv
  naming_table:
    type: File
    outputSource: assign_mgygs/naming_table
  renamed_genomes:
    type: Directory
    outputSource: assign_mgygs/renamed_genomes

# ------- drep -------
  weights:
    type: File?
    outputSource: drep_subwf/weights_file
  best_cluster_reps_drep:                           # remove
    type: File?
    outputSource: drep_subwf/best_cluster_reps
  mash_drep:                                        # remove
    type: File[]?
    outputSource: drep_subwf/mash_files
  one_clusters:                                     # remove
    type: Directory[]?
    outputSource: drep_subwf/one_genome
  many_clusters:                                    # remove
    type: Directory[]?
    outputSource: drep_subwf/many_genomes
  split_test_helper:                                # remove
    type: File?
    outputSource: drep_subwf/split_text

# ------- clusters_annotation -------
  mash_folder:
    type: Directory?
    outputSource: clusters_annotation/mash_folder

  many_genomes:
    type: Directory[]?
    outputSource: clusters_annotation/many_genomes
  many_genomes_panaroo:
    type: Directory[]?
    outputSource: clusters_annotation/many_genomes_panaroo
  many_genomes_prokka:
    type:
      - 'null'
      - type: array
        items:
          type: array
          items: Directory
    outputSource: clusters_annotation/many_genomes_prokka
  many_genomes_genomes:
    type: Directory[]?
    outputSource: clusters_annotation/many_genomes_genomes

  one_genome_final:
    type: Directory[]?
    outputSource: clusters_annotation/one_genome
  one_genome_genomes_gunc:
    type: File
    outputSource: clusters_annotation/one_genome_genomes_gunc_completed

  mmseqs:
    type: Directory?
    outputSource: clusters_annotation/mmseqs_output
  mmseqs_annotation:
    type: Directory?
    outputSource: clusters_annotation/mmseqs_output_annotation

# ------------ drep-filt --------------
  drep_filt_genomes:
    type: File
    outputSource: filter_genomes/list_drep_filtered

# ------------ GTDB-Tk --------------
  gtdbtk:
    type: Directory?
    outputSource: gtdbtk/gtdbtk_folder

# ------- functional annotation ----------
  ips:
    type: File?
    outputSource: functional_annotation/ips_result

  eggnog_annotations:
    type: File?
    outputSource: functional_annotation/eggnog_annotations
  eggnog_seed_orthologs:
    type: File?
    outputSource: functional_annotation/eggnog_seed_orthologs

# ---------- rRNA -------------
  rrna_out:
    type: Directory
    outputSource: detect_rrna/rrna_outs

  rrna_fasta:
    type: Directory
    outputSource: detect_rrna/rrna_fastas


steps:

# ----------- << checkm for NCBI >> -----------
  checkm_subwf:
    run: sub-wf/checkm-subwf.cwl
    when: $(Boolean(inputs.genomes_folder))
    in:
      genomes_folder: genomes_ncbi
    out:
      - checkm_csv

# ----------- << unite NCBI and ENA >> -----------
  unite_folders:
    run: ../tools/unite_ena_ncbi/unite.cwl
    when: $(Boolean(inputs.ncbi_folder) && Boolean(inputs.ena_folder))
    in:
      ena_folder: genomes_ena
      ncbi_folder: genomes_ncbi
      ena_csv: ena_csv
      ncbi_csv: checkm_subwf/checkm_csv
      outputname: { default: "genomes"}
    out:
      - genomes
      - csv

# ----------- << assign MGYGs >> -----------
  assign_mgygs:
    run: ../tools/genomes-catalog-update/rename_fasta/rename_fasta.cwl
    in:
      genomes:
        source:
          - unite_folders/genomes
          - genomes_ena
          - genomes_ncbi
        pickValue: first_non_null
      prefix: { default: "MGYG"}
      start_number: min_accession_mgyg
      max_number: max_accession_mgyg
      output_filename: { default: "names.tsv"}
      output_dirname: { default: "mgyg_genomes" }
      csv:
        source:
          - unite_folders/csv
          - ena_csv
          - checkm_subwf/checkm_csv
        pickValue: first_non_null
    out:
      - naming_table
      - renamed_genomes
      - renamed_csv

# ---------- dRep + split -----------
  drep_subwf:
    run: sub-wf/drep-subwf.cwl
    in:
      genomes_folder: assign_mgygs/renamed_genomes
      input_csv: assign_mgygs/renamed_csv
      skip_flag: skip_drep_step
    out:
      - many_genomes
      - one_genome
      - mash_files
      - best_cluster_reps
      - weights_file
      - split_text

# ---------- annotation
  clusters_annotation:
    run: sub-wf/subwf-process_clusters.cwl
    in:
      many_genomes: drep_subwf/many_genomes
      mash_folder: drep_subwf/mash_files
      one_genome: drep_subwf/one_genome
      mmseqs_limit_c: mmseqs_limit_c
      mmseqs_limit_i: mmseqs_limit_i
      mmseq_limit_annotation: mmseq_limit_annotation
      gunc_db_path: gunc_db_path
      interproscan_databases: interproscan_databases
      chunk_size_ips: chunk_size_ips
      chunk_size_eggnog: chunk_size_eggnog
      db_diamond_eggnog: db_diamond_eggnog
      db_eggnog: db_eggnog
      data_dir_eggnog: data_dir_eggnog
      csv: assign_mgygs/renamed_csv
    out:
      - mash_folder
      - many_genomes
      - many_genomes_panaroo
      - many_genomes_prokka
      - many_genomes_genomes
      - one_genome
      - one_genome_genomes_gunc_completed
      - one_genome_genomes_gunc_failed
      - mmseqs_output
      - mmseqs_output_annotation
      - cluster_representatives

# ----------- << functional annotation >> ------
  functional_annotation:
    run: sub-wf/functional_annotation.cwl
    in:
      input_faa: clusters_annotation/cluster_representatives
      interproscan_databases: interproscan_databases
      chunk_size_ips: chunk_size_ips
      chunk_size_eggnog: chunk_size_eggnog
      db_diamond_eggnog: db_diamond_eggnog
      db_eggnog: db_eggnog
      data_dir_eggnog: data_dir_eggnog
    out:
      - ips_result
      - eggnog_annotations
      - eggnog_seed_orthologs

# ----------- << get genomes dereplicated genomes and GUNC-passed >> ------
  filter_genomes:
    run: ../tools/filter_drep_genomes/filter_drep_genomes.cwl
    in:
      genomes: assign_mgygs/renamed_genomes
      clusters: drep_subwf/split_text
      gunc_passed: clusters_annotation/one_genome_genomes_gunc_completed
      outdirname: {default: deperlicated_genomes}
    out:
      - drep_filtered_genomes
      - list_drep_filtered

# ----------- << GTDB - Tk >> -----------
  gtdbtk:
    when: $(!Boolean(inputs.skip_flag))
    run: ../tools/gtdbtk/gtdbtk.cwl
    in:
      skip_flag: skip_gtdbtk_step
      drep_folder: filter_genomes/drep_filtered_genomes
      gtdb_outfolder: { default: 'gtdb-tk_output' }
      refdata: gtdbtk_data
    out: [ gtdbtk_folder ]

# ---------- << detect rRNA >> ---------
  detect_rrna:
    run: sub-wf/detect_rrna_subwf.cwl
    in:
      filtered_genomes: filter_genomes/drep_filtered_genomes
      cm_models: cm_models
    out: [rrna_outs, rrna_fastas]