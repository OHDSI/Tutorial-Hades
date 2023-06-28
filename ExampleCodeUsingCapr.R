library(DatabaseConnector)
library(Capr)
library(CirceR)
library(CohortGenerator)

# Using DuckDB
connection <- connect(dbms = "duckdb", server = "d:/temp/allergies_cdm.duckdb")

# Using Eunomia
connection <- connect(Eunomia::getEunomiaConnectionDetails())

cdmDatabaseSchema <- "main"
cohortDatabaseSchema <- "main"
cohortTable <- "cohort"

# Create a cohort definition ---------------------------------------------------
hypertensiveDisorder <- cs(
  descendants(316866),
  name = "Hypertensive disorder"
)
hypertensiveDisorder <- getConceptSetDetails(hypertensiveDisorder, connection, cdmDatabaseSchema)
lisinopril <- cs(
  descendants(1308216),
  name = "Lisinopril"
)
lisinopril <- getConceptSetDetails(lisinopril, connection, cdmDatabaseSchema)
hydrochlorothiazide <- cs(
  descendants(974166),
  name = "Hydrochlorothiazide"
)
lisinoprilNewUsers <- cohort(
  entry = entry(
    drug(lisinopril, firstOccurrence()),
    observationWindow = continuousObservation(priorDays = 365)
  ),
  attrition = attrition(
    "prior hypertensive disorder" = withAll(
      atLeast(1, condition(hypertensiveDisorder), duringInterval(eventStarts(-Inf, 0)))
    )
  ),
  exit = exit(endStrategy = drugExit(lisinopril, 
                                     persistenceWindow = 30, 
                                     surveillanceWindow = 0))
)

# Create cohort using definition -----------------------------------------------
json <- as.json(lisinoprilNewUsers)
sql <- buildCohortQuery(json, createGenerateOptions(generateStats = FALSE))
cohortDefinitionSet <- data.frame(cohortId = 1, 
                                  cohortName = "New users of lisinopril",
                                  sql = sql)
cohortTableNames <- getCohortTableNames(cohortTable = cohortTable)
createCohortTables(connection = connection,
                   cohortDatabaseSchema = cohortDatabaseSchema,
                   cohortTableNames = cohortTableNames)
generateCohortSet(connection = connection,
                  cdmDatabaseSchema = cdmDatabaseSchema,
                  cohortDatabaseSchema = cohortDatabaseSchema,
                  cohortTableNames = cohortTableNames,
                  cohortDefinitionSet = cohortDefinitionSet)

# Query cohorts ----------------------------------------------------------------
querySql(connection, "SELECT * FROM main.cohort")

disconnect(connection)
