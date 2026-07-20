from sqlalchemy import Column, Integer, String, Float, Boolean, ForeignKey, DateTime, Text
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from usr.database.base import Base


class Receta(Base):
    __tablename__ = "recetas"
    __table_args__ = {'extend_existing': True}

    id = Column(Integer, primary_key=True, index=True)
    nombre = Column(String(200), nullable=False)
    tipo = Column(String(20), nullable=False)
    producto_base_id = Column(Integer, ForeignKey("productos.id"), nullable=True)
    producto_final_id = Column(Integer, ForeignKey("productos.id"), nullable=True)
    cantidad_producida = Column(Float, default=1)
    activo = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    componentes = relationship("RecetaComponente", back_populates="receta", cascade="all, delete-orphan")

    def __repr__(self):
        return f"<Receta(id={self.id}, nombre='{self.nombre}', tipo='{self.tipo}')>"


class RecetaComponente(Base):
    __tablename__ = "receta_componentes"
    __table_args__ = {'extend_existing': True}

    id = Column(Integer, primary_key=True, index=True)
    receta_id = Column(Integer, ForeignKey("recetas.id"), nullable=False)
    producto_id = Column(Integer, ForeignKey("productos.id"), nullable=False)
    cantidad = Column(Float, nullable=False)
    unidad = Column(String(20), default="unidad")
    tipo_componente = Column(String(20), nullable=False)

    receta = relationship("Receta", back_populates="componentes")
    producto = relationship("Producto")

    def __repr__(self):
        return f"<RecetaComponente(id={self.id}, receta_id={self.receta_id}, producto_id={self.producto_id})>"
