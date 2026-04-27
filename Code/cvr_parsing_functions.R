library(dplyr)

get_sessions_df = function(session, sessionIdx){
  attributes(session)
  original = session$Original
  cards = original$Cards[[1]]
  session_v = c(sessionIdx, session$TabulatorId, session$BatchId,
                session$RecordId, session$CountingGroupId, session$ImageMask,
                session$SessionType, session$VotingSessionIdentifier,
                session$UniqueVotingIdentifier, 
                original$PrecinctPortionId, original$BallotTypeId, 
                original$IsCurrent, cards$Id, cards$KeyInId, cards$PaperIndex) # error when no KeyInId
  return(session_v)
}

create_sessions_df = function(sessions, session_idx_offset = 0){
  num_sessions = length(sessions)
  sessions_df = as.data.frame(t(sapply(c(1:num_sessions), 
                                       function(sessionIdx) 
                                         get_sessions_df(sessions[[sessionIdx]],
                                                         sessionIdx + session_idx_offset))))
  colnames(sessions_df) = c("SessionIdx", "TabulatorId", "BatchId", "RecordId",
                            "CountingGroupId", "ImageMask", "SessionType",
                            "VotingSessionIdentifier", "UniqueVotingIdentifier",
                            "Original_PrecinctPortionId", "Original_BallotTypeId",
                            "Original_IsCurrent", "Cards_Id", #"Cards_KeyInId", 
                            "Cards_PaperIndex")
  sessions_df$SessionIdx = as.integer(sessions_df$SessionIdx)
  sessions_df$Original_PrecinctPortionId = as.integer(sessions_df$Original_PrecinctPortionId)
  return(sessions_df)
}

get_contests_df = function(idx, session){
  cards = session$Original$Cards[[1]]
  contest_df = as.data.frame(t(sapply(cards$Contests, 
                                      function(contest) as.integer(c(idx, 
                                                          contest$Id, 
                                                          contest$ManifestationId, 
                                                          contest$Undervotes, 
                                                          contest$Overvotes)))))
  return(contest_df)
}

get_card_outstacks_df = function(idx, session){
  outstacks = lapply(session$Original$Cards[[1]]$OutstackConditionIds, function(OutstackConditionId) as.data.frame(t(c(idx, OutstackConditionId))))
  return(bind_rows(outstacks))
}

marks_from_contest = function(session_idx, contest){
  marks = contest$Marks
  num_marks = length(marks)
  if (num_marks > 0){
    return(sapply(c(1:length(marks)), 
                  function(mark_idx) {
                    mark = marks[[mark_idx]]
                    return(c(session_idx, 
                             contest$Id,
                             mark_idx,
                             mark$CandidateId,
                             mark$ManifestationId,
                             ifelse(is.null(mark$PartyId),
                                    NA,
                                    mark$PartyId),
                             mark$Rank, 
                             ifelse(is.null(mark$WriteinIndex),
                                    NA,
                                    mark$WriteinIndex),
                             mark$MarkDensity,
                             ifelse(is.null(mark$WriteinDensity),
                                    NA,
                                    mark$WriteinDensity),
                             mark$IsAmbiguous, 
                             mark$IsVote))
                  }))
  } else {
    return(list())
  }
}

get_marks_df = function(idx, session){
  marks_by_contest = lapply(session$Original$Cards[[1]]$Contests, 
                            function(contest) as.data.frame(t(
                              marks_from_contest(idx, contest)
                              
                            )))
  marks_by_contest = marks_by_contest[sapply(marks_by_contest, length) > 0]
  marks_df = bind_rows(marks_by_contest)
  return(marks_df)
}

get_contest_outstacks_df = function(idx, session){
  outstack_by_contest = lapply(session$Original$Cards[[1]]$Contests,
                               function(contest) as.data.frame(t(sapply(
                                 contest$OutstackConditionIds,
                                 function(OutstackCondition) c(idx, contest$Id, OutstackCondition)))))
  outstack_by_contest = outstack_by_contest[sapply(outstack_by_contest, length) > 0]
  contest_outstacks_df = bind_rows(outstack_by_contest)
  return(contest_outstacks_df)
}

get_mark_outstacks = function(session_idx, contest_id, mark_idx, mark){
  mark_outstacks_list = t(sapply(mark$OutstackConditionIds, function(outstackCondition) c(session_idx, contest_id, mark_idx, outstackCondition)))
  mark_outstacks_list = as.data.frame(mark_outstacks_list)
  return(mark_outstacks_list)
}

get_contest_mark_outstacks = function(session_idx, contest){
  marks = contest$Marks
  num_marks = length(marks)
  if (num_marks > 0){
    contest_mark_outstacks = lapply(c(1:num_marks), function(mark_idx) get_mark_outstacks(session_idx, contest$Id, mark_idx, marks[[mark_idx]])) 
    contest_mark_outstacks = contest_mark_outstacks[sapply(contest_mark_outstacks, function(mark_outstacks) length(mark_outstacks) > 0)]
    contest_mark_outstacks = contest_mark_outstacks[sapply(contest_mark_outstacks, function(mark_outstacks) ncol(mark_outstacks)) > 0]
    return(bind_rows(contest_mark_outstacks))
  }
}

get_session_mark_outstacks = function(session_idx, session){
  contests = session$Original$Cards[[1]]$Contests
  num_contests = length(contests)
  if (num_contests > 0){
    session_mark_outstacks = lapply(contests, function(contest) get_contest_mark_outstacks(session_idx, contest))
    session_mark_outstacks = session_mark_outstacks[sapply(session_mark_outstacks, function(contest_outstacks) length(contest_outstacks) > 0)]
    session_mark_outstacks = session_mark_outstacks[sapply(session_mark_outstacks, function(contest_outstacks) ncol(contest_outstacks)) > 0]
    return(bind_rows(session_mark_outstacks))
  }
}
