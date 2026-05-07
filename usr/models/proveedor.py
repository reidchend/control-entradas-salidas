from sqlalchemy import Column, Integer, String, Text, DateTime
from sqlalchemy.sql import func
from usr.database.base import Base


class Proveedor(Base):
    __tablename__ = "proveedores"
    __table_args__ = {'extend_existing': True}
    
    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(200), unique=True, nullable=False, index=True)
    rif = Column(String(50), nullable=True)
    telefono = Column(String(50), nullable=True)
    email = Column(String(100), nullable=True)
    direccion = Column(Text, nullable=True)
    contacto = Column(String(100), nullable=True)
    observaciones = Column(Text, nullable=True)
    estado = Column(String(20), default="Activo", comment="Activo, Inactivo")
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    def __repr__(self):
        return f"<Proveedor(id={self.id}, nombre='{self.nombre}', estado='{self.estado}')>"