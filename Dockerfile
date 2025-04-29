# Use official GlassFish image from Docker Hub
FROM glassfish:latest

# Copy your WAR file into the autodeploy directory
# Replace `your-app.war` with your actual WAR file name
COPY your-app.war /opt/glassfish5/glassfish/domains/domain1/autodeploy/

# Expose default HTTP and HTTPS ports
EXPOSE 8080 8181

# Start GlassFish server (already default CMD in base image)
