from sqlalchemy import Column, Integer, String, Float, ForeignKey, DateTime, Boolean, Text
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from usr.database.base import Base

class Requisicion(Base):
    __tablename__ = "requisiciones"
    __table_args__ = {'extend_existing': True}

    id = Column(Integer, primary_key=True, index=True)
    numero = Column(String(50), unique=True, nullable=False)
    numero_secuencial = Column(Integer, nullable=False)
    origen = Column(String(50), nullable=False)
    destino = Column(String(50), nullable=False)
    estado = Column(String(20), default="pendiente")
    observaciones = Column(Text, nullable=True)
    creada_por = Column(String(100), nullable=True)
    procesada_por = Column(String(100), nullable=True)
    fecha_procesamiento = Column(DateTime(timezone=True), nullable=True)
    fecha_creacion = Column(DateTime(timezone=True), server_default=func.now())
    actualizada = Column(DateTime(timezone=True), onupdate=func.now())

    detalles = relationship("RequisicionDetalle", back_populates="requisicion", cascade="all, delete-orphan")

    def __repr__(self):
        return f"<Requisicion(numero='{self.numero}', origen='{self.origen}', destino='{self.destino}')>"


class RequisicionDetalle(Base):
    __tablename__ = "requisicion_detalles"
    __table_args__ = {'extend_existing': True}

    id = Column(Integer, primary_key=True, index=True)
    requisicion_id = Column(Integer, ForeignKey("requisiciones.id"), nullable=False)
    producto_id = Column(Integer, ForeignKey("productos.id"), nullable=True)
    ingrediente = Column(String(200), nullable=False)
    cantidad = Column(Float, nullable=False)
    unidad = Column(String(50), default="unidad")
    cantidad_surtida = Column(Float, default=0)

    requisicion = relationship("Requisicion", back_populates="detalles")
    producto = relationship("Producto")

    def __repr__(self):
        return f"<RequisicionDetalle(ingrediente='{self.ingrediente}', cantidad={self.cantidad})>"
