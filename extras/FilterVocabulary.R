# Code for filtering a synthea database, by removing any concepts from the vocab that do not appear
# in the data (including ancestors). Also fixes some inconsistencies with CDM.
library(DatabaseConnector)
library(dplyr)

sourceDatabaseFile <- "~/Downloads/database-1M.duckdb"
targetDatabaseFile <- "~/Downloads/database-1M_filtered.duckdb"

# Select concepts used in the CDM ------------------------------------------------------------------
connection <- connect(dbms = "duckdb", server = sourceDatabaseFile)
tables <- getTableNames(connection, "main")
# Note: Excluding concept_class, domain and vocabulary from vocab tables. We want to keep their
# concept IDs:
vocabTables <- c("concept", 
                 "concept_ancestor", 
                 "concept_relationship", 
                 "concept_synonym", 
                 "drug_strength", 
                 "source_to_source_vocab_map",
                 "source_to_standard_vocab_map")
nonVocabTables <- tables[!tables %in% vocabTables]
conceptIds <- c()
# Todo: add unit concepts found in drug_strength table
for (table in nonVocabTables) {
  message(sprintf("Searching table %s", table))
  fields <- DatabaseConnector::dbListFields(connection, paste("main", table, sep = "."))
  fields <- fields[grepl("concept_id$", fields)]
  for (field in fields) {
    message(sprintf("- Searching field %s", field))
    sql <- "SELECT DISTINCT @field FROM main.@table;"
    conceptIds <- unique(c(conceptIds, renderTranslateQuerySql(connection = connection, 
                                                               sql = sql,
                                                               table = table, 
                                                               field = field)[, 1]))
  }
}

# Expand with all parents
insertTable(connection = connection,
            tableName = "#cids",
            data = tibble(concept_id = conceptIds),
            tempTable = TRUE)
sql <- "SELECT DISTINCT ancestor_concept_id 
FROM main.concept_ancestor 
INNER JOIN #cids
  ON descendant_concept_id = concept_id;"
ancestorConceptIds <- renderTranslateQuerySql(connection, sql)[, 1]
conceptIds <- unique(c(conceptIds, ancestorConceptIds))

# Filter data to selected concept IDs --------------------------------------------------------------
insertTable(connection = connection,
            tableName = "#cids",
            data = tibble(concept_id = conceptIds),
            tempTable = TRUE,
            dropTableIfExists = TRUE)

unlink(targetDatabaseFile)
connectionFiltered <- connect(dbms = "duckdb", server = targetDatabaseFile)
sql <- readLines("https://raw.githubusercontent.com/OHDSI/CommonDataModel/main/inst/ddl/5.4/duckdb/OMOPCDM_duckdb_5.4_ddl.sql")
sql <- SqlRender::render(paste(sql, collapse = "\n"), cdmDatabaseSchema = "main")
# Convert all non-concept IDs to BIGINT because data requires this:
sql <- gsub("concept_id BIGINT", "concept_id integer", gsub("_id integer", "_id BIGINT", sql))
executeSql(connectionFiltered, sql)

fixDates <- function(data) { 
  # For some reason dates in source database vocab tables are stored as numeric (not compatible with
  # CDM), so convert them to Date:
  for (field in colnames(data)[grepl("_date", colnames(data), ignore.case = TRUE)]) {
    data[, field] <- as.Date(as.character(data[, field]), format("%Y%m%d"))
  }
  return(data)
}

# Filter vocab tables
for (table in vocabTables) {
  message(sprintf("Filtering table %s", table))
  fields <- DatabaseConnector::dbListFields(connection, paste("main", table, sep = "."))
  fields <- fields[grepl("concept_id", fields)]
  sql <- paste0("SELECT * FROM main.@table WHERE ",
                paste(paste(fields, "IN (SELECT concept_id FROM #cids)"), collapse = " AND "),
                ";")
  data <- renderTranslateQuerySql(connection, sql, table = table)
  colnames(data) <- tolower(colnames(data))
  data <- fixDates(data)
  insertTable(connection = connectionFiltered,
              tableName = table,
              data = data,
              tempTable = FALSE,
              createTable = FALSE,
              dropTableIfExists = FALSE,
              progressBar = TRUE)
}

# Copy non-vocab tbables
for (table in nonVocabTables) {
  message(sprintf("Copying table %s", table))
  sql <- "SELECT * FROM main.@table;"
  data <- renderTranslateQuerySql(connection, sql, table = table)
  colnames(data) <- tolower(colnames(data))
  if (table == "cdm_source") {
    # Avoid non-null constrain:
    data$source_release_date = Sys.Date()
    data$cdm_release_date = Sys.Date()
  }
  if (table == "observation") {
    # Remove erroneous field in source data:
    data$`cast(observation_source_value as varchar)` <- NULL
  }
  insertTable(connection = connectionFiltered,
              tableName = table,
              data = data,
              tempTable = FALSE,
              createTable = FALSE,
              dropTableIfExists = FALSE,
              progressBar = TRUE)
}

# Don't create indices. This will double the file size:
# sql <- readLines("https://raw.githubusercontent.com/OHDSI/CommonDataModel/main/inst/ddl/5.4/duckdb/OMOPCDM_duckdb_5.4_indices.sql")
# sql <- SqlRender::render(paste(sql, collapse = "\n"), cdmDatabaseSchema = "main")
# executeSql(connectionFiltered, sql)

disconnect(connectionFiltered)
disconnect(connection)


