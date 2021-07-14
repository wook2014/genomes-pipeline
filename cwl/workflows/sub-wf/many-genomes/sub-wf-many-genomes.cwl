#!/usr/bin/env cwl-runner
cwlVersion: v1.0
class: Workflow

requirements:
  SubworkflowFeatureRequirement: {}
  MultipleInputFeatureRequirement: {}
  InlineJavascriptRequirement: {}
  StepInputExpressionRequirement: {}
  ScatterFeatureRequirement: {}

inputs:
  cluster: Directory
  mash_files: File[]
  InterProScan_databases: [string, Directory]
  chunk_size_IPS: int
  chunk_size_eggnog: int
  db_diamond_eggnog: [string?, File?]
  db_eggnog: [string?, File?]
  data_dir_eggnog: [string?, Directory?]

outputs:
  prokka_faa-s:
    type: File[]
    outputSource: prokka/faa

  cluster_folder:
    type: Directory
    outputSource: create_cluster_folder/out
  panaroo_folder:
    type: Directory
    outputSource: return_panaroo_cluster_dir/pool_directory
  prokka_folder:
    type: Directory[]
    outputSource: return_prokka_cluster_dir/dir_of_dir
  genomes_folder:
    type: Directory
    outputSource: create_cluster_genomes/out

  mash_folder:
    type: Directory
    outputSource: return_mash_dir/out


steps:
  preparation:
    run: ../../../utils/get_files_from_dir.cwl
    in:
      dir: cluster
    out: [files]

  prokka:
    run: ../../../tools/prokka/prokka.cwl
    scatter: fa_file
    in:
      fa_file: preparation/files
      outdirname: {default: prokka_output }
    out: [ gff, faa, outdir ]

  panaroo:
    run: ../../../tools/panaroo/panaroo.cwl
    in:
      gffs: prokka/gff
      panaroo_outfolder: {default: panaroo_output }
      threads: {default: 8 }
    out: [ pan_genome_reference-fa, panaroo_dir ]

  translate:
    run: ../../../utils/translate_genes.cwl
    in:
      fa_file: panaroo/pan_genome_reference-fa
      faa_file:
        source: cluster
        valueFrom: $(self.basename)_pan_genome_reference.faa
    out: [ converted_faa ]

  IPS:
    run: ../../chunking-subwf-IPS.cwl
    in:
      flag: gunc/complete-flag
      faa: translate/converted_faa
      chunk_size: chunk_size_IPS
      InterProScan_databases: InterProScan_databases
    out: [ips_result]

  eggnog:
    run: ../../chunking-subwf-eggnog.cwl
    in:
      faa_file: translate/converted_faa
      chunk_size: chunk_size_eggnog
      db_diamond: db_diamond_eggnog
      db: db_eggnog
      data_dir: data_dir_eggnog
      cpu: { default: 16 }
    out: [annotations, seed_orthologs]

# --------------------------------------- result folder -----------------------------------------

  get_mash_file:
    run: ../../../utils/get_file_pattern.cwl
    in:
      list_files: mash_files
      pattern:
        source: cluster
        valueFrom: $(self.basename)
    out: [ file_pattern ]

  create_cluster_folder:
    run: ../../../utils/return_directory.cwl
    in:
      list:
        - translate/converted_faa
        - IPS/ips_result
        - eggnog/annotations
        - eggnog/seed_orthologs
        - get_mash_file/file_pattern
      dir_name:
        source: cluster
        valueFrom: cluster_$(self.basename)
    out: [ out ]

  create_cluster_genomes:
    run: ../../../utils/return_directory.cwl
    in:
      list: preparation/files
      dir_name:
        source: cluster
        valueFrom: cluster_$(self.basename)/genomes
    out: [ out ]

  return_prokka_cluster_dir:
    run: ../../../utils/return_dir_of_dir.cwl
    scatter: directory
    in:
      directory: prokka/outdir
      newname:
        source: cluster
        valueFrom: cluster_$(self.basename)
    out: [ dir_of_dir ]

  return_panaroo_cluster_dir:
    run: ../../../utils/return_dir_of_dir.cwl
    in:
      directory_array:
        linkMerge: merge_nested
        source:
          - panaroo/panaroo_dir
      newname:
        source: cluster
        valueFrom: cluster_$(self.basename)
    out: [ pool_directory ]

# ----------- << mash trees >> -----------
  process_mash:
    scatter: input_mash
    run: ../../../tools/mash2nwk/mash2nwk.cwl
    in:
      input_mash: mash_files
    out: [mash_tree]

  return_mash_dir:
    run: ../../../utils/return_directory.cwl
    in:
      list: process_mash/mash_tree
      dir_name: { default: 'mash_trees' }
    out: [ out ]