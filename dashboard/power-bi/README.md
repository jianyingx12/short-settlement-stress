# Power BI build files

This folder contains the theme and DAX measures for the dashboard. The database
objects are built by `python -m src.reporting.run`.

Power BI Desktop is required to create and verify the final report. It is not
installed in the current development environment, so a PBIX file and rendered
screenshots are not included yet. Do not substitute mock images for verified
dashboard screenshots.

The intended file name is `short-selling-settlement-stress.pbix`. Detailed page,
model, connection, and refresh instructions are in the private dashboard
documentation.
