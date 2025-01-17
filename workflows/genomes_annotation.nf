/*
    ~~~~~~~~~~~~~~~~~~
     Input validation
    ~~~~~~~~~~~~~~~~~~
*/
ch_ena_genomes = channel.fromPath(params.ena_genomes, checkIfExists: true)
ch_ena_genomes_checkm = file(params.ena_genomes_checkm, checkIfExists: true)

// TODO: Validate
ch_mgyg_index_start = channel.value(params.mgyg_start)
ch_mgyg_index_end = channel.value(params.mgyg_end)

ch_genomes_information = file("NO_FILE_GENOME_CAT")
ch_study_genomes_information = file("NO_FILE_STUDY_CAT")

if (params.genomes_information) {
    ch_genomes_information = file(params.genomes_information)
}
if (params.study_genomes_information) {
    ch_study_genomes_information = file(params.study_genomes_information)
}

// TODO: Add help message with parameters

/*
    ~~~~~~~~~~~~~~~~
        Imports
    ~~~~~~~~~~~~~~~~
*/

include { PREPARE_DATA } from '../subworkflows/prepare_data'
include { DREP_SWF } from '../subworkflows/drep_swf'
include { DREP_LARGE_SWF } from '../subworkflows/drep_large_catalogue_swf'
include { PROCESS_MANY_GENOMES } from '../subworkflows/process_many_genomes'
include { PROCESS_SINGLETON_GENOMES } from '../subworkflows/process_singleton_genomes'
include { MMSEQ_SWF } from '../subworkflows/mmseq_swf'
include { ANNOTATE } from '../subworkflows/annotate'
include { GTDBTK_AND_METADATA } from '../subworkflows/gtdbtk_and_metadata'
include { KRAKEN_SWF } from '../subworkflows/kraken_swf'

include { MASH_TO_NWK } from '../modules/mash2nwk'
include { FUNCTIONAL_ANNOTATION_SUMMARY } from '../modules/functional_summary'
include { DETECT_NCRNA } from '../modules/detect_ncrna'
include { INDEX_FNA } from '../modules/index_fna'
include { ANNONTATE_GFF } from '../modules/annotate_gff'
include { GENOME_SUMMARY_JSON } from '../modules/genome_summary_json'
include { IQTREE as IQTREE_BAC } from '../modules/iqtree'
include { IQTREE as IQTREE_AR } from '../modules/iqtree'
include { GENE_CATALOGUE } from '../modules/gene_catalogue'
include { MASH_SKETCH } from '../modules/mash_sketch'
include { CRISPRCAS_FINDER } from '../modules/crisprcasfinder'
include { AMRFINDER_PLUS } from '../modules/amrfinder_plus'

/*
    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Channels for ref databases and input parameters
    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

ch_gtdb_db = file(params.gtdb_db)
ch_gunc_db = file(params.gunc_db)
ch_interproscan_db = file(params.interproscan_db)

ch_eggnog_db = file(params.eggnog_db)
ch_eggnog_diamond_db = file(params.eggnong_diamond_db)
ch_eggnog_data_dir = file(params.eggnong_data_dir)

ch_rfam_rrna_models = file(params.rfam_rrna_models)
ch_rfam_ncrna_models = file(params.rfam_ncrna_models)

ch_geo_metadata = file(params.geo_metadata)
ch_kegg_classes = file(params.kegg_classes)
ch_genome_prefix = channel.value(params.genome_prefix)

ch_mmseq_coverage_threshold = channel.value(params.mmseq_coverage_threshold) // def: 0.8
ch_biome = channel.value(params.biome)
ch_ftp_name = channel.value(params.ftp_name)
ch_ftp_version = channel.value(params.ftp_version)

ch_amrfinder_plus_db = file(params.amrfinder_plus_db)

/*
    ~~~~~~~~~~~~~~~~~~
       Run workflow
    ~~~~~~~~~~~~~~~~~~
*/

workflow GAP {

    PREPARE_DATA(
        ch_ena_genomes,
        ch_ena_genomes_checkm,
        channel.empty(), // ncbi, we are ignoring this ATM
        ch_mgyg_index_start,
        ch_mgyg_index_end,
        ch_genome_prefix,
        ch_genomes_information,
        ch_study_genomes_information
    )

    // needs a more elegant solution here
    dereplicated_genomes = channel.empty()

    if ( !params.xlarge ) {
        DREP_SWF(
            PREPARE_DATA.out.genomes,
            PREPARE_DATA.out.genomes_checkm,
            PREPARE_DATA.out.extra_weight_table
        )
        dereplicated_genomes = DREP_SWF
    } else {
        DREP_LARGE_SWF(
            PREPARE_DATA.out.genomes,
            PREPARE_DATA.out.genomes_checkm,
            PREPARE_DATA.out.extra_weight_table
        )
        dereplicated_genomes = DREP_LARGE_SWF
    }

    MASH_TO_NWK(
        dereplicated_genomes.out.mash_splits | flatten
    )

    PROCESS_MANY_GENOMES(
        dereplicated_genomes.out.many_genomes_fna_tuples
    )

    PROCESS_SINGLETON_GENOMES(
        dereplicated_genomes.out.single_genomes_fna_tuples,
        PREPARE_DATA.out.genomes_checkm.first(),
        ch_gunc_db
    )

    MMSEQ_SWF(
        PROCESS_MANY_GENOMES.out.prokka_faas.map({ it[1] }).collectFile(name: "pangenome_prokka.faa"),
        PROCESS_SINGLETON_GENOMES.out.prokka_faa.map({ it[1] }).collectFile(name: "singleton_prokka.faa"),
        PREPARE_DATA.out.genomes_name_mapping.first(),
        ch_mmseq_coverage_threshold
    )

    cluster_reps_faas = PROCESS_MANY_GENOMES.out.rep_prokka_faa.mix(
        PROCESS_SINGLETON_GENOMES.out.prokka_faa
    )

    cluster_reps_fnas = PROCESS_MANY_GENOMES.out.rep_prokka_fna.mix(
        PROCESS_SINGLETON_GENOMES.out.prokka_fna
    )

    cluster_reps_gbks = PROCESS_MANY_GENOMES.out.rep_prokka_gbk.mix(
        PROCESS_SINGLETON_GENOMES.out.prokka_gbk
    )

    all_prokka_fna = PROCESS_SINGLETON_GENOMES.out.prokka_fna.mix(
        PROCESS_MANY_GENOMES.out.prokka_fnas
    )

    species_reps_names_list = PROCESS_MANY_GENOMES.out.rep_prokka_fna.map({ it[0] }) \
        .mix(PROCESS_SINGLETON_GENOMES.out.prokka_fna.map({ it[0] })) \
        .collectFile(name: "species_reps_names_list.txt", newLine: true)

    ANNOTATE(
        MMSEQ_SWF.out.mmseq_90_cluster_tsv,
        MMSEQ_SWF.out.mmseq_90_tarball,
        MMSEQ_SWF.out.mmseq_90_cluster_rep_faa,
        all_prokka_fna,
        cluster_reps_gbks,
        species_reps_names_list,
        ch_interproscan_db,
        ch_eggnog_db,
        ch_eggnog_diamond_db,
        ch_eggnog_data_dir,
        ch_rfam_rrna_models
    )

    GTDBTK_AND_METADATA(
        cluster_reps_fnas.map({ it[1]}).collect(),
        all_prokka_fna.map({ it[1] }).collect(),
        PREPARE_DATA.out.extra_weight_table,
        PREPARE_DATA.out.genomes_checkm,
        ANNOTATE.out.rrna_outs,
        PREPARE_DATA.out.genomes_name_mapping,
        dereplicated_genomes.out.drep_split_text,
        ch_ftp_name,
        ch_ftp_version,
        ch_geo_metadata,
        PROCESS_SINGLETON_GENOMES.out.gunc_failed_txt.ifEmpty("EMPTY"),
        ch_gtdb_db
    )

    /* IQTree need at least 3 sequences. */
    gtdbtk_user_msa_bac120 = GTDBTK_AND_METADATA.out.gtdbtk_user_msa_bac120.first {
        file(it).countFasta() > 2
    }
    IQTREE_BAC(
        gtdbtk_user_msa_bac120,
        channel.value("bac120")
    )
    /* IQTree need at least 3 sequences. */
    gtdbtk_user_msa_ar53 = GTDBTK_AND_METADATA.out.gtdbtk_user_msa_ar53.first {
        file(it).countFasta() > 2
    }
    IQTREE_AR(
        gtdbtk_user_msa_ar53,
        channel.value("ar53")
    )

    cluster_reps_faa = PROCESS_SINGLETON_GENOMES.out.prokka_faa.mix(
        PROCESS_MANY_GENOMES.out.rep_prokka_faa
    )

    faa_and_annotations = cluster_reps_faa.join(
        ANNOTATE.out.ips_annotation_tsvs
    ).join(
        ANNOTATE.out.eggnog_annotation_tsvs
    )

    FUNCTIONAL_ANNOTATION_SUMMARY(
        faa_and_annotations,
        ch_kegg_classes
    )

    DETECT_NCRNA(
        all_prokka_fna,
        ch_rfam_ncrna_models
    )

    INDEX_FNA(
        all_prokka_fna
    )

    cluster_reps_gff = PROCESS_SINGLETON_GENOMES.out.prokka_gff.mix(
        PROCESS_MANY_GENOMES.out.rep_prokka_gff
    )

    // Select the only the reps //
    // Those where the cluster-name and the file name match
    // i.e., such as cluster_name: MGY1 and file MGY1_eggnog.tsv
    reps_ips = ANNOTATE.out.ips_annotation_tsvs.filter {
        it[1].name.contains(it[0])
    }
    reps_eggnog = ANNOTATE.out.eggnog_annotation_tsvs.filter {
        it[1].name.contains(it[0])
    }
    reps_ncrna = DETECT_NCRNA.out.ncrna_tblout.filter {
        it[1].name.contains(it[0])
    }

    CRISPRCAS_FINDER(
        cluster_reps_fnas
    )

    AMRFINDER_PLUS(
        cluster_reps_fnas.join(
            cluster_reps_faa
        ).join(
            cluster_reps_gff
        )
    )

    // REPS //
    ANNONTATE_GFF(
        cluster_reps_gff.join(
            reps_ips
        ).join(
           reps_eggnog
        ).join(
            ANNOTATE.out.sanntis_annotation_gffs
        ).join(
            reps_ncrna
        ).join(
            CRISPRCAS_FINDER.out.hq_gff
        ).join(
            AMRFINDER_PLUS.out.amrfinder_tsv
        )
    )

    /* This operation will generate a list of tuples for the json generation
    * Example of one element on the list;
    * tuple (
        val(cluster),
        file(annotated_gff),
        file(coverage_summary),
        file(cluster_faa),
        file(pangenome_fasta), // only for many_genomes clusters otherwise empty
        file(core_genes)       // only for many_genomes clusters otherwise empty
    )
    */
    files_for_json_summary = ANNONTATE_GFF.out.annotated_gff.join(
        FUNCTIONAL_ANNOTATION_SUMMARY.out.coverage
    ).join(
        cluster_reps_faa
    ).join(
        PROCESS_MANY_GENOMES.out.panaroo_pangenome_fna, remainder: true
    ).join(
        PROCESS_MANY_GENOMES.out.core_genes, remainder: true
    )

    GENOME_SUMMARY_JSON(
        files_for_json_summary,
        GTDBTK_AND_METADATA.out.metadata_tsv.first(),
        ch_biome
    )

    KRAKEN_SWF(
        GTDBTK_AND_METADATA.out.gtdbtk_summary_bac120,
        GTDBTK_AND_METADATA.out.gtdbtk_summary_arc53,
        cluster_reps_fnas.map({ it[1] })
    )

    cluster_rep_ffn = PROCESS_SINGLETON_GENOMES.out.prokka_ffn.mix(
        PROCESS_MANY_GENOMES.out.rep_prokka_ffn
    )

    GENE_CATALOGUE(
        cluster_rep_ffn.map({ it[1] }).collectFile(name: "cluster_reps.ffn", newLine: true),
        MMSEQ_SWF.out.mmseq_100_cluster_tsv
    )

    MASH_SKETCH(
        all_prokka_fna.map({ it[1] }).collect()
    )
}
