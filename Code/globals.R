library(jsonlite)
CVR_DIR = "../Data/CVR_Export/"

load_manifest = function(manifest_name){
  manifest_file = paste0(CVR_DIR, manifest_name, "Manifest.json")
  manifest_data = jsonlite::read_json(manifest_file)$List
  manifest_df = do.call(rbind.data.frame, manifest_data)
  return(manifest_df)
}

SESSIONS_DF = readRDS(paste0(CVR_DIR, "sessions_df.rData"))
SESSIONS_DF$SessionIdx = as.integer(rownames(SESSIONS_DF))
SESSIONS_DF$Original_PrecinctPortionId = as.integer(SESSIONS_DF$Original_PrecinctPortionId)

PRECINCT_PORTION_DF = load_manifest("PrecinctPortion")
PRECINCT_DF = load_manifest("Precinct")

PP_to_P_DF = PRECINCT_PORTION_DF %>%
  rename(PrecinctPortionId = Id, PrecinctPortionDescription = Description) %>%
  full_join(PRECINCT_DF, join_by(PrecinctId == Id)) %>%
  rename(PrecinctDescription = Description) %>%
  select(PrecinctPortionId, PrecinctPortionDescription, PrecinctId, PrecinctDescription)

cm_file = paste0(CVR_DIR, "CandidateManifest.json")
candidate_manifest = jsonlite::read_json(cm_file)$List
for(i in 1:length(candidate_manifest)){
  if (length(candidate_manifest[[i]]$Affiliations)==0){
    candidate_manifest[[i]]$Affiliations=0
  }else{
    candidate_manifest[[i]]$Affiliations=candidate_manifest[[i]]$Affiliations[[1]]
  }
}
CANDIDATE_DF = do.call(rbind.data.frame, candidate_manifest)


MARKS_DF = readRDS(paste0(CVR_DIR, "marks_df.rdata"))
CONTEST_OUTSTACKS_DF = readRDS(paste0(CVR_DIR, "contest_outstacks_df.rdata"))
MARK_OUTSTACKS_DF = readRDS(paste0(CVR_DIR, "mark_outstacks_df.rdata"))

CONTEST_DF = load_manifest("contest")
OUTSTACK_DF = load_manifest("OutstackCondition")
DISTRICT_DF = load_manifest("district")
DISTRICT_PRECINCT_PORTION_DF = load_manifest("districtPrecinctPortion")
DISTRICT_TYPE_DF = load_manifest("DistrictType")

house_district_code = DISTRICT_TYPE_DF[DISTRICT_TYPE_DF$Description == "State House",]$Id
PP_to_HD_DF = DISTRICT_DF %>% 
  filter(DistrictTypeId == house_district_code) %>%
  inner_join(DISTRICT_PRECINCT_PORTION_DF, join_by(Id == DistrictId), multiple = "all") %>%
  select(Description, PrecinctPortionId) %>% 
  rename(HouseDescription = Description)

BALLOT_TYPE_CONTEST_DF = load_manifest("BallotTypeContest")
