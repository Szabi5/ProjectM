# Use an official lightweight Python image
FROM python:3.10-slim

# Set the working directory inside the container
WORKDIR /app

# Copy the requirements file and install the libraries
COPY requirements.txt .
RUN pip install -r requirements.txt

# Copy all your Python code into the container
COPY . .

# Set the "Port" environment variable
ENV PORT 8080

#
# --- THIS IS THE CORRECTED COMMAND ---
#
# We now use the "shell form" (no brackets) so that
# the $PORT variable is correctly replaced by its value (8080).
#
CMD gunicorn --workers=1 --threads=8 --bind=0.0.0.0:$PORT api_server:app