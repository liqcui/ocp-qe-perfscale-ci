# Prow 


## get_periodic_jobs.py

This file is used to create a detailed worksheet of all of the current "periodic" jobs that are being run in our prow system 

Details include: "Test Name", "Cloud Type", "Arch Type", "Version", "Stream type", "Worker_count", "Worker Size", 'Cron Cadencde', "Cron In Words", "Job history Url"

It will create a new tab under this google sheet based on the current date/time
https://docs.google.com/spreadsheets/d/1TM73n4Y6zKRQjvCX8zFM0LwYxChdsncTEGPHpdsS9Ig/edit?usp=sharing

## Dockerfile

This is the base configuration on which the prow jobs are run on, we only need a base python3 installation with oc and kubectl clis