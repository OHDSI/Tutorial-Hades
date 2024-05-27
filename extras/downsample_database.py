import pathlib
import shutil

import duckdb


def downsample_person(database: str, sample_size: int):
    """ Randomly sample the person table to a specific sample_size"""
    conn = duckdb.connect(database)
    # get all tables that have person_id
    tables = (conn.query("SELECT table_name from information_schema.columns "
                         "where column_name = 'person_id' and table_name != 'person'")
              .fetchdf()).values.tolist()

    print(f"Downsampling person to {sample_size}")
    # downsample person_table
    conn.execute(f"""
    CREATE TABLE person_sampled AS
    SELECT * FROM person USING SAMPLE {sample_size};
    """)

    print("Removing deleted persons from event tables")
    for table in tables:
        print(f"Working on table: {table[0]}")
        sql = f"""
        DELETE FROM {table[0]}
        WHERE person_id NOT IN (
            SELECT person_id
            from person_sampled
        );
        """
        conn.execute(sql)
        print(f"Finished working on table: {table[0]}")

    conn.execute("DROP TABLE IF EXISTS person;")

    conn.execute("ALTER TABLE person_sampled RENAME TO person")
    conn.close()


def downsample_measurement(database: str, percentage: float, exclude_from_sampling: list[int]):
    """
    Downsamples the measurement tables while excluding concepts of interest
    :param database: Path to duckdb database
    :param percentage:  How much to downsample to in percentages, i.e. 10.0 for 10%
    :param exclude_from_sampling: Which concepts to exclude from sampling, for example blood pressure [3012888, 3004249]
    :return: Modifies the database
    """
    conn = duckdb.connect(database=database)
    exclude_from_sampling = ", ".join([str(i) for i in exclude_from_sampling])
    conn.execute(f"""
    CREATE TABLE measurement_sampled AS
    WITH CTE_IncludedValues AS (
        SELECT *
        FROM measurement
        WHERE measurement_concept_id IN ({exclude_from_sampling})
    ),
    CTE_ExcludedRowsForSampling AS (
        SELECT *, (SELECT COUNT(*) FROM measurement 
                   where measurement_concept_id NOT IN ({exclude_from_sampling})) * {percentage} / 100.0 as SampleSize
        FROM measurement
        WHERE measurement_concept_id NOT IN ({exclude_from_sampling})
        ORDER BY RANDOM()
    ),
    CTE_Downsampling AS (
        SELECT * EXCLUDE SampleSize
        FROM CTE_ExcludedRowsForSampling
        LIMIT (SELECT CAST(SampleSize AS INT) FROM CTE_ExcludedRowsForSampling LIMIT 1)
    )

    SELECT * FROM CTE_IncludedValues
    UNION ALL
    SELECT * FROM CTE_Downsampling;
    """)
    conn.execute("DROP TABLE measurement;")
    conn.execute("ALTER TABLE measurement_sampled RENAME TO measurement;")
    conn.close()


def downsample_table(database: str, percentage: float, table: str):
    """
    Downsamples a table to a certain percentage of original
    :param database:  Path to duckdb database
    :param percentage:  Percentage to downsample to, e.g. 10.0 for 10%
    :param table:  Name of table
    :return:
    """

    conn = duckdb.connect(database=database)
    conn.execute(f"""
    CREATE TABLE {table}_sampled AS (
        SELECT * FROM {table}
        TABLESAMPLE SYSTEM ({percentage}%)
        );
    """)
    conn.execute(f"DROP TABLE {table};")
    conn.execute(f"ALTER TABLE {table}_sampled RENAME TO {table};")
    conn.close()


def get_concept_column(table: str):
    if "_" in table:
        concept_column = table.split("_")[0] + "_concept_id"
    else:
        concept_column = f"{table}_concept_id"
    return concept_column


def remove_concepts(database: str, table: str, concepts: list[int]):
    """ Remove uninteresting concepts that are frequent in Synthea data"""
    concept_column = get_concept_column(table=table)
    if len(concepts) > 1:
        concept_list = ", ".join([str(i) for i in concepts])
    else:
        concept_list = str(concepts[0])

    conn = duckdb.connect(database=database)
    conn.execute(f"""
    DELETE FROM {table}
    WHERE {concept_list} IN {concept_column};
    """)
    conn.close()


def downsample_concepts(database: str, table: str, concept: int, percentage: float):
    """Downsample concepts that are really frequent"""
    conn = duckdb.connect(database=database)
    concept_column = get_concept_column(table=table)
    id_column = f"{table}_id"
    conn.execute(f"""
    WITH RankedRows AS (
        SELECT
            {id_column},
            ROW_NUMBER() OVER (ORDER BY RANDOM()) as row_number,
            COUNT(*) OVER() AS total_rows
        FROM {table}
        WHERE {concept_column} = {concept}
    )
    DELETE FROM {table}
    WHERE {id_column} IN (
        SELECT {id_column},
        FROM RankedRows
        where row_number > total_rows * {percentage}/100.0
    );
    conn.close()
    """)


def remove_orphan_visits(database: str):
    """
    Removes visits that have no events in them after downsampling event tables
    :param database:
    :return:
    """
    conn = duckdb.connect(database)
    # all tables with visit_occurrence id in them
    conn.execute("""CREATE TEMPORARY TABLE referenced_visits AS
                 SELECT visit_occurrence_id from measurement
                 UNION
                 SELECT visit_occurrence_id from observation
                 UNIO_N
                 SELECT visit_occurrence_id from condition_occurrence
                 UNION
                 SELECT visit_occurrence_id from drug_exposure
                 UNION
                 SELECT visit_occurrence_id from device_exposure
                 UNION
                 SELECT visit_occurrence_id from procedure_occurrence""")
    # remove visits without events from visit_occurrence and visit_detail
    print("Remove orphan visits from visit_detail")
    conn.execute("""
    DELETE FROM visit_detail
    WHERE visit_occurrence_id IN (
    SELECT vo.visit_occurrence_id
    FROM visit_detail vo
    LEFT JOIN referenced_visits rv
    ON vo.visit_occurrence_id = rv.visit_occurrence_id
    where rv.visit_occurrence_id IS NULL);
    """)
    print("Remove orphan visits")
    conn.execute("""
    DELETE FROM visit_occurrence
    WHERE visit_occurrence_id IN (
    SELECT vo.visit_occurrence_id
    FROM visit_detail vo
    LEFT JOIN referenced_visits rv
    ON vo.visit_occurrence_id = rv.visit_occurrence_id
    where rv.visit_occurrence_id IS NULL);
    """)
    conn.close()


def main(database: str):
    downsample_person(database=database, sample_size=1_000_000)

    # downsample measurement without affecting blood pressure measurements
    percentage = 10.0
    print(f"Downsampling measurement table to {percentage}% keeping blood pressure measurements")
    downsample_measurement(database=database,
                           percentage=percentage,
                           exclude_from_sampling=[3012888, 3004249])

    print(f"Downsampling procedure_occurrence to {percentage}% of original")
    downsample_table(database=database,
                     percentage=percentage,
                     table="procedure_occurrence")
    print(f"Downsampling observation to {percentage}% of original")
    downsample_table(database=database,
                     percentage=10.0,
                     table="observation")

    # Remove concepts from measurement: Pain severity and pre-post weight difference during dialysis,
    # together these concepts are ~10% of the table
    print("Remove paint severity and pre-post dialysis weight difference from measurement")
    remove_concepts(database=database,
                    table="measurement",
                    concepts=[43055141, 44786664])

    # downsample dialysis which is ~20% of procedure_occurrence table
    print("Downsample dialysis concepts in procedure_occurrence")
    downsample_concepts(database=database,
                        table="procedure_occurrence",
                        concept=4146536,
                        percentage=5.0)

    # remove concepts  from procedures such as:
    #   4627459 , Assessment of health and social needs
    #   4326177 , Medication reconciliation
    #   35621997 , Assessment using AUDIT-C
    # together these are ~ 20% of the table as well
    print("Removing frequent uninteresting concepts from procedure_occurrence")
    remove_concepts(database=database,
                    table="procedure_occurrence",
                    concepts=[4627459, 4326177, 35621997])

    # Now after removing a bunch of events I need to remove visits that don't have any events anymore
    print("Remove visits without events after event downsampling")
    remove_orphan_visits(database=database)

    # finally I need to export and import the database so its size is updated
    print("Export-Import database")
    conn = duckdb.connect(database=database)
    conn.execute("""
        EXPORT DATABASE "/tmp/duckdb_export/" (FORMAT PARQUET);
    """)

    database = pathlib.Path(database)
    new_database = database.parent.joinpath(f"{database.stem}-1M{database.suffix}")
    pathlib.Path.unlink(database)
    conn = duckdb.connect(database=str(new_database))
    conn.execute("""
        IMPORT DATABASE "/tmp/duckdb/export/"
    """)
    shutil.rmtree("/tmp/duckdb/export/")


if __name__ == '__main__':
    database_path = "~/database/hades-tutorial/database.duckdb"
    main(database=database_path)
