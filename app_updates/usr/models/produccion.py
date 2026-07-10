from sqlalchemy import Column, Integer, String, Float, ForeignKey, DateTime, Text
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from usr.database.base import Base


class Produccion(Base):
    __tablename__ = "producciones"
    __table_args__ = {'extend_existing': True}

    id = Column(Integer, primary_key=True, index=True)
    receta_id = Column(Integer, ForeignKey("recetas.id"), nullable=False)
    cantidad = Column(Float, nullable=False)
    estado = Column(String(20), default="completado")
    usuario = Column(String(100), nullable=True)
    observaciones = Column(Text, nullable=True)
    fecha_produccion = Column(DateTime(timezone=True), server_default=func.now())
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    receta = relationship("Receta")
    detalles = relationship("ProduccionDetalle", back_populates="produccion", cascade="all, delete-orphan")

    def __repr__(self):
        return f"<Produccion(id={self.id}, receta_id={self.receta_id}, cantidad={self.cantidad})>"


class ProduccionDetalle(Base):
    __tablename__ = "produccion_detalles"
    __table_args__ = {'extend_existing': True}

    id = Column(Integer, primary_key=True, index=True)
    produccion_id = Column(Integer, ForeignKey("producciones.id"), nullable=False)
    producto_id = Column(Integer, ForeignKey("productos.id"), nullable=False)
    tipo = Column(String(10), nullable=False)
    cantidad = Column(Float, nullable=False)
    unidad = Column(String(20), default="unidad")
    movimiento_id = Column(Integer, nullable=True)

    produccion = relationship("Produccion", back_populates="detalles")
    producto = relationship("Producto")

    def __repr__(self):
        return f"<ProduccionDetalle(id={self.id}, tipo='{self.tipo}', cantidad={self.cantidad})>"
