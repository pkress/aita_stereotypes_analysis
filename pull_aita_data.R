##################-
### Author: Peter Kress
### Date: 2022/03/06
### Purpose: Pull AITA comments and replies for aita posts
##################-

##################-
# Initialize Workspace ----
##################-
## Paths ----
setwd("~/Documents/Personal Projects/AITA/")

## Packages ----

if(!require("pacman")) install.packages("pacman")
library(pacman)
p_load(data.table, magrittr, stringr, ggplot2)

## Handy Functions ----
`%p%` = paste0

month_diff = function(d1, d2){
  12*(year(d2) - year(d1)) + (month(d2) - month(d1))
}

make_title = function(x){ str_to_title(gsub("_", " ", x))}

##################-
# Read in Data ----
##################-

aita = fread("data/raw/aita_clean.csv")


##################-
# Functions to Pull from Reddit JSON ----
##################-

#' Pull data from a reddit post
#' 
#' @param page url to reddit post with .json suffix
#' @return list with post data, top comments data, additional comments data, top replies for each comment, and additional replies for each comment.
#' @examples
#' page = "https://www.reddit.com/r/AmItheAsshole/comments/e5k3z2.json"
#' page_data = get_page_data(page)
get_page_data = function(page){
  
  pagedata = RJSONIO::fromJSON(page)
  
  post_list = pagedata[[1]][["data"]][["children"]][[1]]
  post_data = get_non_repl_data(post_list) %>%
    .[["data"]]
  
  comment_data = pagedata[[2]][["data"]][["children"]]
  comment_data_out = lapply(comment_data, \(x){
    non_repl_data = get_non_repl_data(x)
    reply_data = NULL
    if(class(x$data$replies)=="list"){
      reply_data = get_replies(x)
    }
    out = list(non_repl = non_repl_data, replies = reply_data)
    return(out)
  })
  
  comment_data_df = lapply(comment_data_out, \(x){
    if(x$non_repl$type=="main") x$non_repl$data[, post_id:=post_data$id][] else NULL
    }) %>% 
    rbindlist(fill =T)
  
  comment_more_df = lapply(comment_data_out, \(x){
    if(x$non_repl$type!="main") x$non_repl$data[, post_id:=post_data$id][] else NULL
  }) %>% 
    rbindlist(fill =T)
  
  replies_df = lapply(comment_data_out, \(x){
    if(!is.null(x$replies))  x$replies$data[, post_id:=post_data$id][] else NULL
  }) %>% 
    rbindlist(fill=T)
  
  replies_more_df = lapply(comment_data_out, \(x){
    if(!is.null(x$replies))  x$replies$other[, post_id:=post_data$id][] else NULL
  }) %>% 
    rbindlist(fill=T)
  
  out = list(post = post_data, comments = comment_data_df, comments_more = comment_more_df
             , replies = replies_df, replies_more = replies_more_df)
  return(out)
}


#' Retrieve replies to a reddit comment
#' 
#' @param comment Comment for which replies are desired
#' @return list with the replies and data as well as hidden "more" replies
#' @examples
#' page = "https://www.reddit.com/r/AmItheAsshole/comments/e5k3z2.json"
#' pagedata = RJSONIO::fromJSON(page)
#' comment = pagedata[[2]][["data"]][["children"]][[1]]
#' replies = get_replies(comment)
get_replies = function(comment){
  out = lapply(comment$data$replies$data$children, get_non_repl_data)
  main_data = lapply(out[unlist(lapply(out, `[[`, "type"))=="main"], `[[`, "data") %>% 
    rbindlist(fill = T)
  main_data[, comment_id := comment$data$id]
  other_data = lapply(out[unlist(lapply(out, `[[`, "type"))!="main"], `[[`, "data") %>% 
    rbindlist(fill = T)
  other_data[, comment_id := comment$data$id]
  return(list(data = main_data, other = other_data))
}

#' Retrieve non reply (comment level) data for a comment
#' 
#' @param comment Comment for which replies are desired
#' @return list w/ comment level data and a type indicator for "see more" comments
#' @examples
#' page = "https://www.reddit.com/r/AmItheAsshole/comments/e5k3z2.json"
#' pagedata = RJSONIO::fromJSON(page)
#' comment = pagedata[[2]][["data"]][["children"]][[1]]
#' comment_data =  get_non_repl_data(comment)
get_non_repl_data = function(comment){
  ### Needed to keep from list-columns
  dropcols = c("all_awardings", "gildings", "link_flair_richtext", "media_embed"
               , "user_reports", "secure_media_embed", "author_flair_richtext"
               , "awarders", "treatment_tags", "mod_reports", "replies")
  
  out = as.data.table(comment$data[setdiff(names(comment$data),dropcols)])
  type = fifelse(nrow(out)>1, "other", "main")
  return(list(data = out, type = type))
}

#' Get data for "see more" type comments, deleting full post text to save memory
#' 
#' @param page Page of direct link to a comment on a post, or reply to a comment.
#' @return page data, with post data excluding full text
#' @examples
#' page = "https://www.reddit.com/r/AmItheAsshole/comments/e5k3z2.json"
#' pagedata = RJSONIO::fromJSON(page)
#' comment = pagedata[[2]][["data"]][["children"]][[1]]
#' comment_page = paste0(comment$permalink, ".json")
#' comment_page_data =  get_extra_data(comment_page)
get_extra_data = function(page){
  out = get_page_data(page)
  ### Delete full chars text to save memory
  out$post[, c("selftext", "selftext_html"):=NULL][]
  return(out)
}

#' Pull all comment level and reply inforamtion for a list of comment pages
#' 
#' @param commentlist list of comment ids to pull data from
#' @param url url of reddit post where comment ids were pulled from 
#' @return comments, replies, and "see more" replies for all comments in the list.
#' @examples
#' page = "https://www.reddit.com/r/AmItheAsshole/comments/e5k3z2.json"
#' pagedata = RJSONIO::fromJSON(page)
#' comments = pagedata[[2]][["data"]][["children"]]
#' commentlist = lapply(comments, `[[`, "id") %>% unlist()
#' url = pagedata[[1]][["data"]][["children"]][[1]]$url
#' comment_data = get_comments(commentlist, url)
get_comments = function(commentlist, url){
  out = lapply(commentlist, \(x, url){
    extras = get_extra_data(url%p%x%p%".json")
    
    return(list(extra_comments = extras$comments
                         , extra_replies = extras$replies
                         , extra_replies_more = extras$replies_more))
  }, url = url) 
  
  comments = lapply(out, `[[`, "extra_comments") %>% 
    rbindlist(fill = T)
  replies = lapply(out, `[[`, "extra_replies") %>% 
    rbindlist(fill = T)
  replies_more = lapply(out, `[[`, "extra_replies_more") %>% 
    rbindlist(fill = T)
  return(list(comments = comments
              , replies = replies
              , replies_more = replies_more))
}

#' pull post and comment level info for top comments from a list of reddit posts
#' 
#' @param page reddit post page to pull data from
#' @param max_comments number of comments to retrieve for each post.
#' @return post data and top comments data, including count of replies for the comments. 
#' @examples
#' page = "https://www.reddit.com/r/AmItheAsshole/comments/e5k3z2.json"
#' max_comments = 50
#' page_post_and_comments = get_post_and_comments(page, max_comments)
get_post_and_comments = function(page, max_comments){
  cat("\n\n"%p%page)
  page_data = get_page_data(page)
  comments = page_data$comments
  reply_counts = page_data$replies[, .N, comment_id]
  extra_reply_counts = page_data$replies_more[, .N, comment_id]
  reply_count_total = rbind(reply_counts, extra_reply_counts) %>% 
    .[, .(reply_count = sum(N)), comment_id]
  comments[
    reply_count_total
    , reply_count:=i.reply_count
    , on = c("id" = "comment_id")
    ][
    is.na(reply_count)
    , reply_count:=0
    ]
  
  ## Add extra comments
  if(nrow(page_data$comments_more)>0) {
    extra_comments = get_comments(page_data$comments_more[1:min(c(max_comments,.N)),children]
                                  , URLencode(page_data$post$url))
    
    ex_reply_counts = NULL
    ex_extra_reply_counts = NULL
    if(nrow(extra_comments$replies)>0){
      ex_reply_counts = extra_comments$replies[, .N, comment_id]  
    }
    if(nrow(extra_comments$replies_more)){
      ex_extra_reply_counts = extra_comments$replies_more[, .N, comment_id]
    }
    if(!is.null(ex_reply_counts)|!is.null(ex_extra_reply_counts)){
      ex_reply_count_total = rbind(ex_reply_counts, ex_extra_reply_counts) %>% 
        .[, .(reply_count = sum(N)), comment_id]
      ex_comments = extra_comments$comments[
        ex_reply_count_total
        , reply_count:=i.reply_count
        , on = c("id" = "comment_id")
      ][
        is.na(reply_count)
        , reply_count:=0
      ]
    } else{
      ex_comments = extra_comments$comments[
        , reply_count:=0
      ]
    }
    
    comments = rbind(comments, ex_comments, fill = T)
  }
  
  return(list(post = page_data$post, comments = comments)) 
}


##################-
# Pull comments and data for top posts ----
##################-

pull_data_by_rank = function(pull_ranks, max_comments, data = aita){
  top_posts = data[order(-score), id][pull_ranks]
  
  top_post_pages = "https://www.reddit.com/r/AmItheAsshole/comments/"%p%top_posts%p%".json"
  
  top_post_info = lapply(top_post_pages, get_post_and_comments
                         , max_comments = max_comments)
  
  top_posts = lapply(top_post_info, `[[`, "post") %>% 
    rbindlist(fill = T)
  top_post_comments = lapply(top_post_info, `[[`, "comments") %>% 
    rbindlist(fill = T)
  fwrite(top_posts, "data/intermediate/top_"%p%min(pull_ranks)%p%"_"%p%max(pull_ranks)%p%"_posts.csv")
  fwrite(top_post_comments, "data/intermediate/top_"%p%min(pull_ranks)%p%"_"%p%max(pull_ranks)%p%"_posts_top_"%p%max_comments%p%"_comments.csv")
  
  
}

pull_ranks = 1:300 ## which posts to pull, ordered by votes
max_comments = 50 ## Number of additional comments to pull after top comments
pull_data_by_rank(pull_ranks, max_comments) ## Pull and save data

